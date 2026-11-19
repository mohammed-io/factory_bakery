# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'numeric constraint hygiene (issue #38)' do
  include DefineConstantMacros

  describe 'other_than is enforced (audit probe 14)' do
    let!(:model) do
      define_model('OtherThanValue', value: :integer) do
        validates :value, numericality: { other_than: 5 }
      end
    end

    it 'never bakes the forbidden value across 50 draws' do
      records = 50.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:value)).not_to include(5)
      expect(records).to all(be_valid)
    end

    it 're-samples within the remaining bounds when the forbidden value is the only other option' do
      narrow = define_model('NarrowOtherThanValue', value: :integer) do
        validates :value, numericality: {
          greater_than_or_equal_to: 4,
          less_than_or_equal_to: 5,
          other_than: 5
        }
      end

      records = 20.times.map { FactoryBakery.bake(narrow) }

      expect(records.map(&:value)).to all(eq(4))
      expect(records).to all(be_valid)
    end

    it 'enforces other_than on float columns' do
      floats = define_model('OtherThanRate', rate: :float) do
        validates :rate, numericality: { equal_to: 0.5, other_than: 0.5 }
      end

      expect { FactoryBakery.bake(floats, fill_optional: true) }
        .to raise_error(FactoryBakery::Error, /OtherThanRate#rate.*other_than.*attempts/m)
    end

    it 'enforces other_than on date columns' do
      fixed = Date.new(2024, 1, 1)
      dates = define_model('OtherThanDay', day: :date) do
        validates :day, comparison: {
          greater_than_or_equal_to: fixed,
          less_than_or_equal_to: fixed,
          other_than: fixed
        }
      end

      expect { FactoryBakery.bake(dates, fill_optional: true) }
        .to raise_error(FactoryBakery::Error, /OtherThanDay#day.*other_than.*attempts/m)
    end

    it 'enforces other_than on datetime columns' do
      fixed = Time.utc(2024, 1, 1)
      datetimes = define_model('OtherThanMoment', moment: :datetime) do
        validates :moment, comparison: {
          greater_than_or_equal_to: fixed,
          less_than_or_equal_to: fixed,
          other_than: fixed
        }
      end

      expect { FactoryBakery.bake(datetimes, fill_optional: true) }
        .to raise_error(FactoryBakery::Error, /OtherThanMoment#moment.*other_than.*attempts/m)
    end
  end

  describe 'odd/even parity stays within bounds' do
    it 'never steps past an upper bound when forcing even values' do
      model = define_model('EvenUpperBound', value: :integer) do
        validates :value, numericality: { even: true, less_than_or_equal_to: 7 }
      end

      records = 30.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:value)).to all(satisfy { |value| value.even? && value <= 7 })
      expect(records).to all(be_valid)
    end

    it 're-samples within a tight even bound instead of emitting 8' do
      model = define_model('TightEvenBound', value: :integer) do
        validates :value, numericality: {
          even: true,
          greater_than_or_equal_to: 6,
          less_than_or_equal_to: 7
        }
      end

      records = 20.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:value)).to all(eq(6))
      expect(records).to all(be_valid)
    end

    it 'respects an in: range when forcing parity' do
      model = define_model('EvenInRange', value: :integer) do
        validates :value, numericality: { in: 1..7, even: true }
      end

      records = 20.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:value)).to all(satisfy { |value| value.even? && (1..7).cover?(value) })
      expect(records).to all(be_valid)
    end
  end

  describe 'exclusion exhaustion' do
    it 'raises a contextual error instead of emitting the only forbidden integer value' do
      model = define_model('TinyExcludedNumber', value: :integer) do
        validates :value, numericality: { greater_than_or_equal_to: 1, less_than_or_equal_to: 1 }
        validates :value, exclusion: { in: [1] }
      end

      expect { FactoryBakery.bake(model) }
        .to raise_error(FactoryBakery::Error, /TinyExcludedNumber#value.*\[1\].*attempts/m)
    end

    it 'raises a contextual error instead of emitting the only forbidden float value' do
      model = define_model('TinyExcludedRate', rate: :float) do
        validates :rate, numericality: { equal_to: 0.5 }
        validates :rate, exclusion: { in: [0.5] }
      end

      expect { FactoryBakery.bake(model) }
        .to raise_error(FactoryBakery::Error, /TinyExcludedRate#rate.*0\.5.*attempts/m)
    end
  end
end
