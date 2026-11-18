# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'FactoryBakery public trait API' do
  describe '.bake with traits' do
    it 'overrides a base declaration for the same attribute and merges non-overlapping attributes' do
      model = define_model('TraitUser', name: :string, role: :string, city: :string) do
        validates :name, presence: true
      end

      FactoryBakery.define(model) do
        name { 'base name' }
        city { 'base city' }

        trait :admin do
          name { 'admin name' }
          role { 'admin' }
        end
      end

      record = FactoryBakery.bake(model, :admin)

      expect(record.name).to eq('admin name')
      expect(record.role).to eq('admin')
      expect(record.city).to eq('base city')
      expect(record).to be_valid
    end

    it 'applies multiple traits in order, with later traits overriding earlier ones' do
      model = define_model('MultiTraitUser', name: :string, role: :string, level: :string)

      FactoryBakery.define(model) do
        name { 'base' }

        trait :admin do
          name { 'admin' }
          role { 'admin' }
        end

        trait :vip do
          name { 'vip' }
          level { 'gold' }
        end
      end

      record = FactoryBakery.bake(model, :admin, :vip)

      expect(record.name).to eq('vip')
      expect(record.role).to eq('admin')
      expect(record.level).to eq('gold')
    end

    it 'lets call-site overrides beat trait values' do
      model = define_model('OverrideTraitUser', name: :string)

      FactoryBakery.define(model) do
        trait :admin do
          name { 'from trait' }
        end
      end

      record = FactoryBakery.bake(model, :admin, name: 'from call site')

      expect(record.name).to eq('from call site')
    end

    it 'lets call-site overrides beat every trait when multiple are applied' do
      model = define_model('OverrideMultiTraitUser', name: :string, role: :string)

      FactoryBakery.define(model) do
        trait :admin do
          name { 'admin' }
          role { 'admin' }
        end

        trait :vip do
          name { 'vip' }
        end
      end

      record = FactoryBakery.bake(model, :admin, :vip, name: 'from call site')

      expect(record.name).to eq('from call site')
      expect(record.role).to eq('admin')
    end

    it 'raises a clear error naming the trait and definition for an undeclared trait' do
      model = define_model('NoSuchTraitUser', name: :string)

      FactoryBakery.define(model) do
        name { 'base' }
      end

      expect { FactoryBakery.bake(model, :missing) }
        .to raise_error(FactoryBakery::Error, /:missing.*NoSuchTraitUser/)
    end

    it 'raises a clear error when a trait is requested without any definition' do
      model = define_model('UndefinedTraitUser', name: :string)

      expect { FactoryBakery.bake(model, :admin) }
        .to raise_error(FactoryBakery::Error, /:admin.*UndefinedTraitUser/)
    end

    it 'still fills undeclared attributes heuristically when traits are applied' do
      model = define_model('HeuristicTraitUser', name: :string, age: :integer, city: :string) do
        validates :name, presence: true
        validates :age, numericality: { greater_than: 0 }
        validates :city, presence: true
      end

      FactoryBakery.define(model) do
        trait :admin do
          name { 'admin' }
        end
      end

      record = FactoryBakery.bake(model, :admin)

      expect(record.name).to eq('admin')
      expect(record.age).to be_a(Integer)
      expect(record.age).to be > 0
      expect(record.city).to be_a(String)
      expect(record.city).not_to be_empty
      expect(record).to be_valid
    end

    it 're-evaluates trait blocks on every bake' do
      model = define_model('LazyTraitUser', code: :string)
      counter = 0

      FactoryBakery.define(model) do
        trait :counted do
          code do
            counter += 1
            "code-#{counter}"
          end
        end
      end

      expect(FactoryBakery.bake(model, :counted).code).to eq('code-1')
      expect(FactoryBakery.bake(model, :counted).code).to eq('code-2')
    end
  end

  describe '.bake! with traits' do
    it 'persists a baked record with trait values applied' do
      model = define_model('PersistedTraitUser', name: :string) do
        validates :name, presence: true
      end

      FactoryBakery.define(model) do
        trait :admin do
          name { 'persisted admin' }
        end
      end

      record = FactoryBakery.bake!(model, :admin)

      expect(record).to be_persisted
      expect(record.name).to eq('persisted admin')
    end
  end
end
