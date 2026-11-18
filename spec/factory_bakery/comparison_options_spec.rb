# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'comparison/numericality option forms (issue #35)' do
  include DefineConstantMacros

  describe 'symbol bounds on numeric columns (audit probe 16)' do
    let!(:model) do
      define_model('SymbolPrice', price: :float, discount: :float) do
        validates :discount, comparison: { less_than: :price }
      end
    end

    it 'resolves the symbol against the baked object without raising' do
      records = 10.times.map { FactoryBakery.bake(model) }

      expect(records).to all(be_valid)
      records.each do |record|
        expect(record.discount).to be < record.price
      end
    end

    it 'resolves a numericality symbol bound on integer columns too' do
      model = define_model('SymbolCount', total: :integer, used: :integer) do
        validates :used, numericality: { less_than: :total }
      end

      records = 10.times.map { FactoryBakery.bake(model) }

      expect(records).to all(be_valid)
      records.each { |record| expect(record.used).to be < record.total }
    end

    it 'resolves a reference to an attribute declared later in column order' do
      model = define_model('LatePrice', discount: :float, price: :float) do
        validates :discount, comparison: { less_than: :price }
      end

      records = 10.times.map { FactoryBakery.bake(model) }

      expect(records).to all(be_valid)
      records.each { |record| expect(record.discount).to be < record.price }
    end

    it 'resolves a reference to a call-site override' do
      model = define_model('OverriddenPrice', price: :float, discount: :float) do
        validates :discount, comparison: { less_than: :price }
      end

      record = FactoryBakery.bake(model, price: 200.0)

      expect(record.price).to eq(200.0)
      expect(record.discount).to be < 200.0
      expect(record).to be_valid
    end
  end

  describe 'symbol bounds on dates (audit probe 17)' do
    let!(:model) do
      define_model('SymbolPeriod', start_date: :date, end_date: :date) do
        validates :end_date, comparison: { greater_than: :start_date }
      end
    end

    it 'resolves the referenced date to a real bound' do
      records = 10.times.map { FactoryBakery.bake(model) }

      expect(records).to all(be_valid)
      records.each { |record| expect(record.end_date).to be > record.start_date }
    end

    it 'resolves symbol bounds on datetime columns' do
      model = define_model('SymbolWindow', opens_at: :datetime, closes_at: :datetime) do
        validates :closes_at, comparison: { greater_than: :opens_at }
      end

      records = 5.times.map { FactoryBakery.bake(model) }

      expect(records).to all(be_valid)
      records.each { |record| expect(record.closes_at).to be > record.opens_at }
    end
  end

  describe 'proc bounds' do
    it 'calls a record-aware proc at bake time and uses its result' do
      calls = []
      model = define_model('ProcBoundPrice', price: :float, discount: :float) do
        validates :discount, comparison: {
          less_than: lambda { |record|
            calls << record
            record.price / 2
          }
        }
      end

      expect(calls).to be_empty
      record = FactoryBakery.bake(model, price: 200.0)

      expect(calls.length).to eq(1)
      expect(calls.first).to be_a(model)
      expect(record.discount).to be < 100.0
      expect(record).to be_valid
    end

    it 'accepts a zero-arity proc' do
      model = define_model('ZeroArityBound', value: :float) do
        validates :value, numericality: { less_than: -> { 25.0 } }
      end

      records = 10.times.map { FactoryBakery.bake(model) }

      expect(records).to all(be_valid)
      expect(records.map(&:value)).to all(be < 25.0)
    end
  end

  describe 'attributes that constrain each other' do
    let!(:model) do
      define_model('ChainedPrice', cost: :float, price: :float, discount: :float) do
        validates :price, comparison: { greater_than: :cost }
        validates :discount, comparison: { less_than: :price }
      end
    end

    it 'resolves dependencies in order and satisfies both constraints' do
      records = 10.times.map { FactoryBakery.bake(model) }

      expect(records).to all(be_valid)
      records.each do |record|
        expect(record.price).to be > record.cost
        expect(record.discount).to be < record.price
      end
    end
  end

  describe 'cyclic symbol bounds' do
    it 'falls back to an unconstrained draw rather than raising' do
      model = define_model('CyclicBounds', alpha: :float, beta: :float) do
        validates :alpha, comparison: { less_than: :beta }
        validates :beta, comparison: { less_than: :alpha }
      end

      record = nil
      expect { record = FactoryBakery.bake(model) }.not_to raise_error
      expect(record.alpha).to be_a(Float)
      expect(record.beta).to be_a(Float)
    end
  end

  describe ':in on comparison options for numeric columns' do
    it 'is honored on a float column' do
      model = define_model('ComparisonInFloat', value: :float) do
        validates :value, comparison: { greater_than: 0, in: 10.0..20.0 }
      end

      records = 10.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:value)).to all(be_between(10.0, 20.0).inclusive)
      expect(records).to all(be_valid)
    end

    it 'is honored on an integer column' do
      model = define_model('ComparisonInInteger', value: :integer) do
        validates :value, comparison: { greater_than: 0, in: 10..20 }
      end

      records = 10.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:value)).to all(be_between(10, 20).inclusive)
      expect(records).to all(be_valid)
    end
  end

  describe 'literal bounds' do
    it 'leaves numericality literals unchanged' do
      model = define_model('LiteralNumericality', value: :float) do
        validates :value, numericality: { greater_than: 10, less_than: 20 }
      end

      records = 20.times.map { FactoryBakery.bake(model) }

      expect(records).to all(be_valid)
      records.each { |record| expect(record.value).to be_between(10, 20).exclusive }
    end

    it 'leaves comparison literals unchanged' do
      model = define_model('LiteralComparison', value: :integer) do
        validates :value, comparison: { greater_than_or_equal_to: 5, less_than_or_equal_to: 8 }
      end

      records = 20.times.map { FactoryBakery.bake(model) }

      expect(records).to all(be_valid)
      records.each { |record| expect(record.value).to be_between(5, 8).inclusive }
    end
  end
end
