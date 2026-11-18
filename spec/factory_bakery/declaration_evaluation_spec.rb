# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'FactoryBakery declaration evaluation' do
  describe 'losing declaration blocks' do
    it 'does not evaluate a declaration overridden at the call site' do
      model = define_model('UnusedOverrideUser', name: :string)
      calls = 0

      FactoryBakery.define(model) do
        name do
          calls += 1
          'from factory'
        end
      end

      record = FactoryBakery.bake(model, name: 'from call site')

      expect(record.name).to eq('from call site')
      expect(calls).to eq(0)
    end

    it 'does not evaluate a declaration shadowed by a trait, and evaluates the trait block once' do
      model = define_model('UnusedBaseUser', name: :string)
      base_calls = 0
      trait_calls = 0

      FactoryBakery.define(model) do
        name do
          base_calls += 1
          'from definition'
        end

        trait :renamed do
          name do
            trait_calls += 1
            'from trait'
          end
        end
      end

      record = FactoryBakery.bake(model, :renamed)

      expect(record.name).to eq('from trait')
      expect(base_calls).to eq(0)
      expect(trait_calls).to eq(1)
    end

    it 'evaluates only the last trait block for an attribute declared by several traits' do
      model = define_model('UnusedTraitUser', name: :string)
      first_calls = 0
      second_calls = 0
      third_calls = 0

      FactoryBakery.define(model) do
        trait(:a) { name { first_calls += 1; 'a' } }
        trait(:b) { name { second_calls += 1; 'b' } }
        trait(:c) { name { third_calls += 1; 'c' } }
      end

      record = FactoryBakery.bake(model, :a, :b, :c)

      expect(record.name).to eq('c')
      expect(first_calls).to eq(0)
      expect(second_calls).to eq(0)
      expect(third_calls).to eq(1)
    end

    it 'evaluates only the last declaration when an attribute is declared twice in a definition' do
      model = define_model('UnusedEarlierUser', name: :string)
      first_calls = 0
      second_calls = 0

      FactoryBakery.define(model) do
        name { first_calls += 1; 'first' }
        name { second_calls += 1; 'second' }
      end

      record = FactoryBakery.bake(model)

      expect(record.name).to eq('second')
      expect(first_calls).to eq(0)
      expect(second_calls).to eq(1)
    end

    it 'does not evaluate a trait block overridden at the call site' do
      model = define_model('UnusedTraitOverrideUser', name: :string)
      calls = 0

      FactoryBakery.define(model) do
        trait :renamed do
          name { calls += 1; 'from trait' }
        end
      end

      record = FactoryBakery.bake(model, :renamed, name: 'from call site')

      expect(record.name).to eq('from call site')
      expect(calls).to eq(0)
    end

    it 'does not insert a row when a losing declaration block bakes a parent with bake!' do
      parent = define_model('UnusedInsertParent', name: :string)
      model = define_model('UnusedInsertUser', name: :string)

      FactoryBakery.define(model) do
        name { FactoryBakery.bake!(parent).name }
      end

      record = FactoryBakery.bake!(model, name: 'from call site')

      expect(record.name).to eq('from call site')
      expect(parent.count).to eq(0)
    end
  end

  describe 'winning declaration blocks' do
    it 'still evaluates other declared blocks when one attribute is overridden' do
      model = define_model('OtherBlocksUser', name: :string, city: :string)
      name_calls = 0
      city_calls = 0

      FactoryBakery.define(model) do
        name { name_calls += 1; 'from factory' }
        city { city_calls += 1; 'from factory' }
      end

      record = FactoryBakery.bake(model, name: 'from call site')

      expect(record.name).to eq('from call site')
      expect(record.city).to eq('from factory')
      expect(name_calls).to eq(0)
      expect(city_calls).to eq(1)
    end

    it 'evaluates the winning block afresh on every bake' do
      model = define_model('FreshEvaluationUser', name: :string)
      calls = 0

      FactoryBakery.define(model) do
        name { "name-#{calls += 1}" }
      end

      expect(FactoryBakery.bake(model).name).to eq('name-1')
      expect(FactoryBakery.bake(model).name).to eq('name-2')
      expect(calls).to eq(2)
    end
  end
end
