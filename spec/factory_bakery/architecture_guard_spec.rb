# frozen_string_literal: true

require 'spec_helper'
require 'open3'

# The enforcement of the framework-agnostic core: no file in the core set may
# reference the ActiveRecord, ActiveModel or Rails constants, so agnosticism
# cannot silently regress. Excluded from the core set are the default mapper
# plugin (lib/factory_bakery/active_record_mapper/**), the opt-in
# associations plugin internals (lib/factory_bakery/associations/**) and the
# Rails integration (which lives inside the mapper plugin directory).
RSpec.describe 'framework-agnostic core architecture guard' do
  CORE_EXCLUSIONS = [
    %r{\Alib/factory_bakery/active_record_mapper(?:\.rb|/|\z)}, # default mapper plugin + Rails integration
    %r{\Alib/factory_bakery/associations(?:/|\z)}               # opt-in associations plugin internals
  ].freeze

  # Constant references, including name-string matching (validator classes
  # are matched by name in the mapper, never in the core) and any textual
  # mention in comments.
  FORBIDDEN_CONSTANT_REFERENCES = /\b(?:ActiveRecord|ActiveModel|Rails)\b/

  # Requiring a framework gem is a dependency, not just a mention.
  FORBIDDEN_FRAMEWORK_REQUIRES =
    %r{\brequire\s*\(?\s*['"](?:rails|active_record|active_model|active_support)['"]}

  def core_files
    Dir.glob('lib/**/*.rb').reject do |path|
      CORE_EXCLUSIONS.any? { |pattern| path.match?(pattern) }
    end.sort
  end

  def violations_in(files, pattern)
    files.flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, index|
        "#{path}:#{index + 1}: #{line.strip}" if line.match?(pattern)
      end
    end
  end

  it 'protects a real core set' do
    expect(core_files).to include(
      'lib/factory_bakery.rb',
      'lib/factory_bakery/bakery_builder.rb',
      'lib/factory_bakery/mapper_registry.rb',
      'lib/factory_bakery/constraint_set.rb',
      'lib/factory_bakery/uniqueness_enforcer.rb',
      'lib/factory_bakery/persistence_verifier.rb',
      'lib/factory_bakery/attribute_fillers/filler_selector.rb',
      'lib/factory_bakery/attribute_fillers/string_filler.rb',
      'lib/factory_bakery/attribute_fillers/value_resolution.rb'
    )

    # The excluded plugin worlds must exist, otherwise the exclusions quietly
    # guard nothing.
    expect(File.exist?('lib/factory_bakery/active_record_mapper.rb')).to be(true)
    expect(File.exist?('lib/factory_bakery/active_record_mapper/mapper.rb')).to be(true)
    expect(File.exist?('lib/factory_bakery/active_record_mapper/railtie.rb')).to be(true)
    expect(File.exist?('lib/factory_bakery/associations/plugin.rb')).to be(true)
  end

  it 'is armed: the excluded mapper plugin really does reference its framework' do
    # A canary proving the pattern catches genuine references. If this ever
    # fails, the core assertions above are guarding nothing.
    expect(File.read('lib/factory_bakery/active_record_mapper/mapper.rb'))
      .to match(FORBIDDEN_CONSTANT_REFERENCES)
  end

  it 'keeps every framework constant reference out of the core set' do
    violations = violations_in(core_files, FORBIDDEN_CONSTANT_REFERENCES)

    expect(violations).to be_empty,
          "framework constants leaked into the framework-agnostic core:\n#{violations.join("\n")}"
  end

  it 'keeps every framework require out of the core set' do
    violations = violations_in(core_files, FORBIDDEN_FRAMEWORK_REQUIRES)

    expect(violations).to be_empty,
          "framework requires leaked into the framework-agnostic core:\n#{violations.join("\n")}"
  end

  it 'loads the gem and bakes a plain target with no framework boot at all' do
    ffaker_lib = File.join(Gem::Specification.find_by_name('ffaker').gem_dir, 'lib')
    code = <<~RUBY
      require 'factory_bakery'

      abort 'the gem must not load the framework on its own' if defined?(Rails)

      class GuardSpecPoro
        attr_accessor :greeting
      end

      FactoryBakery.define(GuardSpecPoro) { greeting { 'framework-free' } }
      value = FactoryBakery.bake(GuardSpecPoro).greeting
      abort 'plain bake is broken outside frameworks' unless value == 'framework-free'

      print 'OK'
    RUBY

    stdout, stderr, status = nil
    Bundler.with_unbundled_env do
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        '-I', ffaker_lib, '-I', File.expand_path('lib'),
        '-e', code
      )
    end

    expect(status).to be_success,
                  "framework-free load failed:\n#{stderr}\n#{stdout}"
    expect(stdout).to eq('OK')
  end
end
