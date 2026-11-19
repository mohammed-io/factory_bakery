# frozen_string_literal: true

require 'spec_helper'
require 'active_model'
require 'timeout'

# Issue #42: format synthesis must be bounded and must actually synthesize
# groups, alternation, inline flags and POSIX character classes (FFaker's
# from_regexp emitted literal garbage for the first three and spun
# unboundedly on the last). Issue #65 moved synthesis onto RegexGeneration.
RSpec.describe 'bounded, real format-regex synthesis (issue #42)' do
  include DefineConstantMacros

  def bake_timed(model)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    record = Timeout.timeout(6) { FactoryBakery.bake(model) }
    [record, Process.clock_gettime(Process::CLOCK_MONOTONIC) - started]
  end

  describe 'POSIX character classes (measured unbounded-spin regression)' do
    it 'bakes a compliant value within the wall-clock bound for [[:alpha:]]' do
      model = define_model('PosixAlphaTag', name: :string) do
        validates :name, format: { with: /\A[[:alpha:]]+\z/ }
      end

      record, elapsed = bake_timed(model)

      expect(record.name).to match(/\A[[:alpha:]]+\z/)
      expect(record).to be_valid
      expect(elapsed).to be < 6
    end

    it 'bakes a compliant value for a POSIX digit class' do
      model = define_model('PosixDigitTag', code: :string) do
        validates :code, format: { with: /\A[[:digit:]]{4}\z/ }
      end

      record, = bake_timed(model)

      expect(record.code).to match(/\A[[:digit:]]{4}\z/)
      expect(record).to be_valid
    end
  end

  describe 'alternation synthesis' do
    it 'synthesizes a compliant value for a grouped alternation (hex colors)' do
      model = define_model('HexColor', hex: :string) do
        validates :hex, format: { with: /\A([0-9a-fA-F]{3}|[0-9a-fA-F]{6})\z/ }
      end

      records = 10.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:hex)).to all(match(/\A([0-9a-fA-F]{3}|[0-9a-fA-F]{6})\z/))
      expect(records).to all(be_valid)
    end

    it 'synthesizes a compliant value for top-level alternation' do
      model = define_model('AlternatingCode', code: :string) do
        validates :code, format: { with: /\A[a-z]+|\d{4}\z/ }
      end

      record = FactoryBakery.bake(model)

      expect(record.code).to match(/\A[a-z]+|\d{4}\z/)
      expect(record.code).not_to include('|')
      expect(record).to be_valid
    end
  end

  describe 'inline flag groups' do
    it 'synthesizes a compliant value for a leading inline flag' do
      model = define_model('InlineFlagCode', code: :string) do
        validates :code, format: { with: /(?i)abc/ }
      end

      record = FactoryBakery.bake(model)

      expect(record.code).to match(/(?i)abc/)
      expect(record.code).not_to include('(')
      expect(record).to be_valid
    end

    it 'synthesizes a compliant value for a scoped inline flag' do
      model = define_model('ScopedFlagCode', code: :string) do
        validates :code, format: { with: /\A(?i:ab)c\z/ }
      end

      record = FactoryBakery.bake(model)

      expect(record.code).to match(/\A(?i:ab)c\z/)
      expect(record).to be_valid
    end
  end

  describe 'unsatisfiable regexes' do
    it 'raises the contextual exhaustion error quickly, without junk' do
      model = define_model('LookaheadCode', code: :string) do
        validates :code, format: { with: /\Afoo(?=bar)\z/ }
      end

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect { FactoryBakery.bake(model) }
        .to raise_error(FactoryBakery::Error, /LookaheadCode#code.*attempts/m)
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 6
    end
  end

  describe 'lookaround' do
    it 'synthesizes a compliant value for a positive lookahead' do
      model = define_model('LookaheadPrefixCode', code: :string) do
        validates :code, format: { with: /\Afoo(?=bar)bar\z/ }
      end

      record = FactoryBakery.bake(model)

      expect(record.code).to eq('foobar')
      expect(record).to be_valid
    end
  end

  describe 'bounded synthesis' do
    it 'abandons a regex whose shortest match exceeds the output bound instead of hanging' do
      model = define_model('OversizedCode', code: :string) do
        validates :code, format: { with: /\A[a-z]{5000}\z/ }
      end

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect { FactoryBakery.bake(model) }
        .to raise_error(FactoryBakery::Error, /OversizedCode#code.*attempts/m)
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 6
    end

    it 'abandons a regex whose repetitions explode instead of hanging' do
      model = define_model('ExplosiveCode', code: :string) do
        validates :code, format: { with: /\A(?:(?:(?:(?:){9}){9}){9}){9}x\z/ }
      end

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect { FactoryBakery.bake(model) }
        .to raise_error(FactoryBakery::Error, /ExplosiveCode#code.*attempts/m)
      expect(Process.clock_gettime(Process::CLOCK_MONOTONIC) - started).to be < 6
    end
  end
end
