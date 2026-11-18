# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'FactoryBakery public define API' do
  describe '.define + .bake' do
    it 'uses declaration block values and still fills undeclared columns heuristically' do
      model = define_model('Cake', name: :string, price: :integer) do
        validates :name, presence: true
        validates :price, numericality: { greater_than: 0 }
      end

      FactoryBakery.define(model) do
        name { 'custom cake' }
      end

      record = FactoryBakery.bake(model)

      expect(record.name).to eq('custom cake')
      expect(record.price).to be_a(Integer)
      expect(record.price).to be > 0
      expect(record).to be_valid
    end

    it 're-evaluates attribute blocks on every bake' do
      model = define_model('Ticketing', code: :string)
      counter = 0

      FactoryBakery.define(model) do
        code { counter += 1; "code-#{counter}" }
      end

      expect(FactoryBakery.bake(model).code).to eq('code-1')
      expect(FactoryBakery.bake(model).code).to eq('code-2')
    end

    it 'keeps uniqueness valid across repeated bakes because blocks are lazy' do
      model = define_model('UniqueEmail', email: :string) do
        validates :email, uniqueness: true
      end
      sequence = 0

      FactoryBakery.define(model) do
        email { sequence += 1; "user#{sequence}@example.com" }
      end

      expect(FactoryBakery.bake!(model)).to be_persisted
      expect(FactoryBakery.bake!(model)).to be_persisted
      expect(model.count).to eq(2)
    end

    it 'lets call-site overrides beat factory declaration blocks' do
      model = define_model('OverrideCake', name: :string)

      FactoryBakery.define(model) do
        name { 'from factory' }
      end

      expect(FactoryBakery.bake(model, name: 'from call site').name).to eq('from call site')
    end

    it 'constructs the object with initialize_with attributes' do
      model = define_model('ConstructorRecord', code: :string) do
        validates :code, presence: true
      end

      FactoryBakery.define(model) do
        initialize_with(code: 'from constructor')
      end

      record = FactoryBakery.bake(model)

      expect(record.code).to eq('from constructor')
      expect(record).to be_valid
    end

    it 'replaces an earlier definition when the same class is registered again' do
      model = define_model('ReRegister', name: :string)

      FactoryBakery.define(model) { name { 'first' } }
      FactoryBakery.define(model) { name { 'second' } }

      expect(FactoryBakery.bake(model).name).to eq('second')
    end

    it 'persists a defined factory through bake!' do
      model = define_model('DefinedPersisted', name: :string) do
        validates :name, presence: true
      end

      FactoryBakery.define(model) { name { 'baked' } }
      record = FactoryBakery.bake!(model)

      expect(record).to be_persisted
      expect(record.name).to eq('baked')
    end

    it 'still fills heuristically when no definition is registered' do
      model = define_model('UndefinedBake', title: :string, count: :integer) do
        validates :title, presence: true
        validates :count, numericality: { greater_than: 0 }
      end

      record = FactoryBakery.bake(model)

      expect(record.title).to be_a(String)
      expect(record.title).not_to be_empty
      expect(record.count).to be > 0
      expect(record).to be_valid
    end
  end
end
