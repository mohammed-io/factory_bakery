# frozen_string_literal: true

require 'spec_helper'

RSpec.describe FactoryBakery::ClassCache do
  it 'memoizes values per class and key, including nil' do
    first = Class.new
    second = Class.new
    calls = 0
    computed = lambda do |result|
      calls += 1
      result
    end
    value = described_class.fetch(first, :value) { computed.call(Object.new) }
    expect(described_class.fetch(first, :value) { computed.call(nil) }).to equal(value)
    expect(described_class.fetch(first, :nil) { computed.call(nil) }).to be_nil
    described_class.fetch(first, :nil) { computed.call(nil) }
    described_class.fetch(first, :other) { Object.new }
    described_class.fetch(second, :value) { Object.new }
    expect(calls).to eq(2)
  end

  it 'clears one class or all classes' do
    first = Class.new
    second = Class.new
    described_class.fetch(first, :key) { 1 }
    described_class.fetch(second, :key) { 2 }
    described_class.clear(first)
    expect(described_class.fetch(first, :key) { 3 }).to eq(3)
    expect(described_class.fetch(second, :key) { 4 }).to eq(2)
    described_class.clear_all
    expect(described_class.fetch(second, :key) { 4 }).to eq(4)
  end

  it 'does not cache for frozen classes and memoizes tables' do
    klass = Class.new.freeze
    expect(described_class.fetch(klass, :key) { Object.new }).not_to equal(
      described_class.fetch(klass, :key) { Object.new }
    )
    mutable = Class.new
    expect(described_class.table(mutable, :map)).to equal(described_class.table(mutable, :map))
  end

  it 'resets through the public API' do
    klass = Class.new
    described_class.fetch(klass, :key) { 1 }
    FactoryBakery.reset_cache!
    expect(described_class.fetch(klass, :key) { 2 }).to eq(2)
  end

  it 'lets a computation fetch another fact of the same class' do
    klass = Class.new
    universe = described_class.fetch(klass, :universe) do
      guards = described_class.fetch(klass, :guards) { %w[id] }
      %w[name id] - guards
    end

    expect(universe).to eq(%w[name])
    expect(described_class.fetch(klass, :guards) { raise 'recomputed' }).to eq(%w[id])
  end

  it 'lets two threads fetch the same fact and agree on one value' do
    klass = Class.new
    values = Array.new(8) { Thread.new { described_class.fetch(klass, :shared) { Object.new } } }.map(&:value)

    expect(values.uniq.size).to eq(1)
  end

  it 'clears a class that was cached and then frozen, and still clears the others' do
    klass = Class.new
    other = Class.new
    described_class.fetch(klass, :key) { :stale }
    described_class.fetch(other, :key) { :kept }
    klass.freeze

    expect { FactoryBakery.reset_cache! }.not_to raise_error
    expect(described_class.fetch(klass, :key) { :recomputed }).to eq(:recomputed)
    # clear_all kept going past the frozen class, so the other class is cleared too.
    expect(described_class.fetch(other, :key) { :recomputed }).to eq(:recomputed)
  end

  it 'recomputes on every call for a frozen class and never stores' do
    klass = Class.new
    described_class.fetch(klass, :key) { :cached }
    klass.freeze
    calls = 0

    results = Array.new(2) do
      described_class.fetch(klass, :key) do
        calls += 1
        :fresh
      end
    end

    expect(results).to all(eq(:fresh))
    expect(calls).to eq(2)
  end

  it 'does not republish a stale value into a table that clear emptied in place' do
    klass = Class.new
    fiber = Fiber.new do
      described_class.fetch(klass, :k) do
        Fiber.yield
        :stale
      end
    end
    fiber.resume

    klass.freeze
    FactoryBakery.reset_cache!
    fiber.resume

    expect(described_class.fetch(klass, :k) { :fresh }).to eq(:fresh)
    expect { FactoryBakery.reset_cache! }.not_to raise_error
  end

  it 'does not re-publish a stale value whose computation was still in flight when the class was cleared' do
    klass = Class.new
    fiber = Fiber.new do
      described_class.fetch(klass, :k) do
        Fiber.yield
        :stale
      end
    end
    fiber.resume

    described_class.clear(klass)
    fiber.resume

    expect(described_class.fetch(klass, :k) { :fresh }).to eq(:fresh)
  end

  describe 'when a schema changes under a model' do
    include DefineConstantMacros

    it 'fills a column added after the first bake once the schema is reloaded' do
      model = define_model('CacheSchemaItem', name: :string) { validates :name, presence: true }
      expect(FactoryBakery.bake(model).attributes).not_to have_key('score')

      model.connection.add_column(model.table_name, :score, :integer)
      model.validates :score, presence: true
      model.reset_column_information

      expect(FactoryBakery.bake(model).score).to be_a(Integer)
    end

    it 'drops the cached facts of every model on reset_cache!' do
      model = define_model('CacheResetItem', name: :string)
      FactoryBakery.bake(model)
      model.connection.add_column(model.table_name, :score, :integer)
      model.validates :score, presence: true
      model.connection.schema_cache.clear!
      model.reset_column_information
      FactoryBakery.reset_cache!

      expect(FactoryBakery.bake(model).score).to be_a(Integer)
    end
  end
end
