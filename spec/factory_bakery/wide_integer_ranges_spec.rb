# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'wide integer ranges (issue #64)' do
  include DefineConstantMacros

  def elapsed_seconds
    before = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - before
  end

  describe 'numericality :in ranges' do
    it 'bakes a billions-wide range instantly with a value inside it' do
      model = define_model('WideRolePosition', position: :integer) do
        validates :position, numericality: { in: -(2**31)..(2**31) }
      end

      record = nil
      elapsed = elapsed_seconds { record = FactoryBakery.bake(model) }

      expect(elapsed).to be < 0.1
      expect(record.position).to be_between(-(2**31), 2**31).inclusive
      expect(record).to be_valid
    end

    it 'respects an exclusive upper bound' do
      model = define_model('ExclusiveRangeValue', value: :integer) do
        validates :value, numericality: { in: 1...10 }
      end

      records = 20.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:value)).to all(be_between(1, 9).inclusive)
      expect(records).to all(be_valid)
    end

    it 'respects an endless range' do
      model = define_model('EndlessRangeValue', value: :integer) do
        validates :value, numericality: { in: 5.. }
      end

      records = 20.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:value)).to all(be >= 5)
      expect(records).to all(be_valid)
    end

    it 'respects a beginless range' do
      model = define_model('BeginlessRangeValue', value: :integer) do
        validates :value, numericality: { in: (..-5) }
      end

      records = 20.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:value)).to all(be <= -5)
      expect(records).to all(be_valid)
    end

    it 'rounds float bounds inward on an integer column' do
      model = define_model('FloatBoundedInteger', value: :integer) do
        validates :value, numericality: { in: 1.2..5.8 }
      end

      records = 20.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:value)).to all(be_between(2, 5).inclusive)
      expect(records).to all(be_valid)
    end

    it 'keeps parity on a wide range' do
      model = define_model('WideOddPosition', position: :integer) do
        validates :position, numericality: { in: -(2**31)..(2**31), odd: true }
      end

      records = 20.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:position)).to all(be_odd)
      expect(records).to all(be_valid)
    end

    it 'keeps other_than on a wide range' do
      model = define_model('WideOtherThanValue', value: :integer) do
        validates :value, numericality: { in: -(2**31)..(2**31), other_than: 0 }
      end

      records = 20.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:value)).not_to include(0)
      expect(records).to all(be_valid)
    end

    it 'keeps exclusions on a wide range' do
      model = define_model('WideExcludedValue', value: :integer) do
        validates :value, numericality: { in: -(2**31)..(2**31) }
        validates :value, exclusion: { in: [0, 1, -1] }
      end

      records = 20.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:value)).not_to include(0, 1, -1)
      expect(records).to all(be_valid)
    end

    it 'deterministically yields the single survivor of a small window' do
      model = define_model('NarrowInRangeValue', value: :integer) do
        validates :value, numericality: { in: 4..5, other_than: 5 }
      end

      records = 20.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:value)).to all(eq(4))
      expect(records).to all(be_valid)
    end
  end

  describe 'infinite endpoints' do
    it 'treats a Float::INFINITY endpoint as an open side' do
      model = define_model('InfiniteRangeValue', value: :integer) do
        validates :value, numericality: { in: 3..Float::INFINITY }
      end

      records = 20.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:value)).to all(be >= 3)
      expect(records).to all(be_valid)
    end
  end

  describe 'inclusion ranges' do
    it 'bakes a wide inclusion range without materializing it' do
      model = define_model('WideInclusionValue', value: :integer) do
        validates :value, inclusion: { in: -(2**31)..(2**31) }
      end

      record = nil
      elapsed = elapsed_seconds { record = FactoryBakery.bake(model) }

      expect(elapsed).to be < 0.1
      expect(record.value).to be_between(-(2**31), 2**31).inclusive
      expect(record).to be_valid
    end
  end
end
