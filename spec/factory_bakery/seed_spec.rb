# frozen_string_literal: true

require 'spec_helper'
require 'logger'
require 'stringio'
require 'open3'

RSpec.describe 'FactoryBakery seed resolution' do
  let(:log) { StringIO.new }
  let(:logger) { Logger.new(log, formatter: FactoryBakery::Seed::LOG_FORMAT) }
  let(:poro) do
    Class.new do
      attr_accessor :label
    end
  end

  def with_env(key, value)
    previous = ENV.fetch(key, nil)
    value.nil? ? ENV.delete(key) : ENV[key] = value
    yield
  ensure
    previous.nil? ? ENV.delete(key) : ENV[key] = previous
  end

  def bake_once
    FactoryBakery.bake(poro)
  end

  around do |example|
    with_env('FACTORY_BAKERY_SEED', nil) { example.run }
  end

  before do
    FactoryBakery.logger = logger
    FactoryBakery.seed = nil
  end

  after do
    # Forget the test framework source again so later examples fall through to
    # the random source, and restore the silent logger the suite uses.
    FactoryBakery.register_test_framework_seed(label: 'Fake', reproduce: 'fake --seed %d') { nil }
    FactoryBakery.seed = nil
    FactoryBakery.logger = Logger.new(nil)
  end

  describe 'source order' do
    it 'uses the Integer seed when the environment variable is unset' do
      FactoryBakery.seed = 1234

      expect(FactoryBakery.seed).to eq(1234)
      expect(log.string).to include(
        '[FactoryBakery] WARN: seed 1234 from FactoryBakery.seed= (not the test framework\'s seed); ' \
        'reproduce with FACTORY_BAKERY_SEED=1234'
      )
    end

    it 'prefers FACTORY_BAKERY_SEED over the Integer seed' do
      with_env('FACTORY_BAKERY_SEED', '77') do
        FactoryBakery.seed = 1234

        expect(FactoryBakery.seed).to eq(77)
        expect(log.string).to include('seed 77 from FACTORY_BAKERY_SEED')
      end
    end

    it 'uses a callable seed when the environment variable is unset, announced as a callable' do
      FactoryBakery.seed = -> { 99 }

      expect(FactoryBakery.seed).to eq(99)
      expect(log.string).to include(
        '[FactoryBakery] WARN: seed 99 from FactoryBakery.seed= (callable) (not the test framework\'s seed); ' \
        'reproduce with FACTORY_BAKERY_SEED=99'
      )
    end

    it 'calls a callable seed lazily, and only once per resolution' do
      calls = 0
      FactoryBakery.seed = lambda {
        calls += 1
        99
      }

      expect(calls).to eq(0)
      expect(FactoryBakery.seed).to eq(99)
      FactoryBakery.seed
      expect(calls).to eq(1)
    end

    it 'accepts any object that responds to call' do
      FactoryBakery.seed = proc { 31 }

      expect(FactoryBakery.seed).to eq(31)
    end

    it 'prefers FACTORY_BAKERY_SEED over a callable seed, without calling it' do
      calls = 0
      with_env('FACTORY_BAKERY_SEED', '77') do
        FactoryBakery.seed = lambda {
          calls += 1
          99
        }

        expect(FactoryBakery.seed).to eq(77)
      end
      expect(calls).to eq(0)
    end

    it 'prefers the Integer seed over the test framework seed' do
      FactoryBakery.register_test_framework_seed(label: 'Fake', reproduce: 'fake --seed %d') { 4242 }
      FactoryBakery.seed = 5

      expect(FactoryBakery.seed).to eq(5)
    end

    it 'prefers a callable seed over the test framework seed' do
      FactoryBakery.register_test_framework_seed(label: 'Fake', reproduce: 'fake --seed %d') { 4242 }
      FactoryBakery.seed = -> { 99 }

      expect(FactoryBakery.seed).to eq(99)
    end

    it 'uses the test framework seed when nothing above is set, announced at INFO' do
      FactoryBakery.register_test_framework_seed(label: 'Fake', reproduce: 'fake --seed %d') { 4242 }

      expect(FactoryBakery.seed).to eq(4242)
      expect(log.string).to eq(
        "[FactoryBakery] INFO: using Fake seed 4242 for generated data (fake --seed 4242 reproduces it)\n"
      )
    end

    it 'falls back to a random seed when the test framework is not running' do
      FactoryBakery.register_test_framework_seed(label: 'Fake', reproduce: 'fake --seed %d') { nil }

      seed = FactoryBakery.seed
      expect(seed).to be_a(Integer)
      expect(log.string).to include(
        "[FactoryBakery] WARN: seed #{seed} from a random choice for this process " \
        "(not the test framework's seed); reproduce with FACTORY_BAKERY_SEED=#{seed}"
      )
    end

    it 'chooses one random seed per process and keeps it' do
      first = FactoryBakery.seed
      second = FactoryBakery.seed

      expect(first).to eq(second)
      expect(log.string.scan('from a random choice').size).to eq(1)
    end

    it 'clears back to the next source when the setting is set to nil' do
      FactoryBakery.seed = -> { 99 }
      FactoryBakery.seed = nil

      expect(FactoryBakery.seed).to be_a(Integer)
      expect(log.string).to include('from a random choice for this process')
    end
  end

  describe 'validation' do
    it 'rejects a seed that is neither an Integer, a callable nor nil' do
      expect { FactoryBakery.seed = 'abc' }.to raise_error(
        ArgumentError, /must be an Integer, a callable returning an Integer, or nil, got "abc"/
      )
    end

    it 'rejects a symbol, which is not callable' do
      expect { FactoryBakery.seed = :build_number }.to raise_error(ArgumentError, /got :build_number/)
    end

    it 'rejects a callable that returns a non-Integer when the seed is resolved' do
      FactoryBakery.seed = -> { '12' }

      expect { FactoryBakery.seed }.to raise_error(
        ArgumentError, /seed callable must return an Integer, got "12"/
      )
    end

    it 'rejects a callable that returns nil instead of falling through to the next source' do
      FactoryBakery.register_test_framework_seed(label: 'Fake', reproduce: 'fake --seed %d') { 4242 }
      FactoryBakery.seed = -> {}

      expect { FactoryBakery.seed }.to raise_error(ArgumentError, /must return an Integer, got nil/)
    end

    it 'rejects a non-integer FACTORY_BAKERY_SEED' do
      with_env('FACTORY_BAKERY_SEED', 'twelve') do
        expect { FactoryBakery.seed }.to raise_error(ArgumentError, /FACTORY_BAKERY_SEED must be an integer/)
      end
    end

    it 'treats a blank FACTORY_BAKERY_SEED as unset' do
      with_env('FACTORY_BAKERY_SEED', '  ') do
        FactoryBakery.seed = 8

        expect(FactoryBakery.seed).to eq(8)
      end
    end
  end

  describe 'announcements' do
    it 'logs once per resolution, however many bakes follow' do
      FactoryBakery.seed = 1234

      3.times { bake_once }

      expect(log.string.scan('seed 1234 from FactoryBakery.seed=').size).to eq(1)
    end

    it 'resolves again, and logs again, after a seed setting changes' do
      FactoryBakery.seed = 1234
      FactoryBakery.seed
      FactoryBakery.seed = 5678

      expect(FactoryBakery.seed).to eq(5678)
      expect(log.string.scan('from FactoryBakery.seed=').size).to eq(2)
    end

    it 'resolves again after switching from an Integer to a callable' do
      FactoryBakery.seed = 1234
      FactoryBakery.seed
      FactoryBakery.seed = -> { 99 }

      expect(FactoryBakery.seed).to eq(99)
      expect(log.string).to include('seed 99 from FactoryBakery.seed= (callable)')
    end

    it 'stays silent when the logger is nil' do
      FactoryBakery.logger = nil
      FactoryBakery.seed = 1234

      expect { FactoryBakery.seed }.not_to raise_error
      expect(log.string).to eq('')
    end
  end

  # The integrations are loaded in a fresh process so their registration and
  # the framework seed they read are the only ones in play.
  describe 'test framework integrations' do
    let(:lib_dir) { File.expand_path('../../lib', __dir__) }
    let(:ffaker_lib) { File.join(Gem::Specification.find_by_name('ffaker').gem_dir, 'lib') }
    let(:bake_three_times) do
      <<~RUBY
        class IntegrationPoro; attr_accessor :label; end
        3.times { FactoryBakery.bake(IntegrationPoro) }
      RUBY
    end

    def run_ruby(prelude, env = {})
      code = "#{prelude}\n#{bake_three_times}"
      Bundler.with_unbundled_env do
        Open3.capture3(env, RbConfig.ruby, '-I', ffaker_lib, '-I', lib_dir, '-e', code)
      end
    end

    it 'takes RSpec\'s seed and announces it once at INFO' do
      prelude = <<~RUBY
        require 'factory_bakery/rspec'
        module RSpec; Config = Struct.new(:seed); def self.configuration = Config.new(12345); end
      RUBY

      _out, err, status = run_ruby(prelude)

      expect(status).to be_success, err
      expect(err).to eq(
        "[FactoryBakery] INFO: using RSpec seed 12345 for generated data (rspec --seed 12345 reproduces it)\n"
      )
    end

    it 'takes Minitest\'s seed and announces it once at INFO' do
      prelude = <<~RUBY
        require 'factory_bakery/minitest'
        module Minitest; def self.seed = 777; end
      RUBY

      _out, err, status = run_ruby(prelude)

      expect(status).to be_success, err
      expect(err).to eq(
        '[FactoryBakery] INFO: using Minitest seed 777 for generated data ' \
        "(bin/rails test --seed 777 reproduces it)\n"
      )
    end

    it 'warns with FACTORY_BAKERY_SEED when the environment variable overrides RSpec' do
      prelude = <<~RUBY
        require 'factory_bakery/rspec'
        module RSpec; Config = Struct.new(:seed); def self.configuration = Config.new(12345); end
      RUBY

      _out, err, status = run_ruby(prelude, 'FACTORY_BAKERY_SEED' => '5')

      expect(status).to be_success, err
      expect(err).to eq(
        "[FactoryBakery] WARN: seed 5 from FACTORY_BAKERY_SEED (not the test framework's seed); " \
        "reproduce with FACTORY_BAKERY_SEED=5\n"
      )
    end

    it 'lets a callable seed override RSpec without touching the framework\'s seed' do
      prelude = <<~RUBY
        require 'factory_bakery/rspec'
        module RSpec; Config = Struct.new(:seed); def self.configuration = Config.new(12345); end
        FactoryBakery.seed = -> { 99 }
      RUBY

      _out, err, status = run_ruby(prelude)

      expect(status).to be_success, err
      expect(err).to eq(
        "[FactoryBakery] WARN: seed 99 from FactoryBakery.seed= (callable) (not the test framework's seed); " \
        "reproduce with FACTORY_BAKERY_SEED=99\n"
      )
    end

    it 'falls back to a random seed when RSpec is not loaded' do
      _out, err, status = run_ruby("require 'factory_bakery/rspec'")

      expect(status).to be_success, err
      expect(err.scan('[FactoryBakery] WARN: seed ').size).to eq(1)
      expect(err).to include('from a random choice for this process')
    end
  end
end
