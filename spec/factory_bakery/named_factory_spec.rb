# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'FactoryBakery named factories and symbol resolution' do
  describe 'define with a symbol target' do
    it 'bakes an instance of the class bound via klass: with the declared values' do
      model = define_model('Customer', name: :string) do
        validates :name, presence: true
      end

      FactoryBakery.define(:customer, klass: model) do
        name { 'Ada' }
      end

      record = FactoryBakery.bake(:customer)

      expect(record).to be_a(model)
      expect(record.name).to eq('Ada')
      expect(record).to be_valid
    end

    it 'resolves a bare symbol lazily at first bake, after the constant exists' do
      expect { FactoryBakery.define(:late_user) { name { 'late' } } }.not_to raise_error

      model = define_model('LateUser', name: :string) do
        validates :name, presence: true
      end

      record = FactoryBakery.bake(:late_user)

      expect(record).to be_a(model)
      expect(record.name).to eq('late')
      expect(record).to be_valid
    end

    it 'camelizes multi-word symbols when resolving a class lazily' do
      FactoryBakery.define(:admin_user) { name { 'admin' } }
      model = define_model('AdminUser', name: :string)

      expect(FactoryBakery.bake(:admin_user)).to be_a(model)
    end

    it 'raises a clear error naming the symbol when the constant is missing, then recovers once it exists' do
      FactoryBakery.define(:missing_later) { name { 'later' } }

      expect { FactoryBakery.bake(:missing_later) }
        .to raise_error(FactoryBakery::Error, /:missing_later/)

      model = define_model('MissingLater', name: :string)
      expect(FactoryBakery.bake(:missing_later)).to be_a(model)
    end
  end

  describe 'baking an unregistered symbol' do
    it 'raises FactoryBakery::Error naming the symbol' do
      expect { FactoryBakery.bake(:unknown) }
        .to raise_error(FactoryBakery::Error, /:unknown/)
    end

    it 'never falls back to constantizing the symbol at bake time' do
      stub_const('Orphan', Class.new)

      expect { FactoryBakery.bake(:orphan) }
        .to raise_error(FactoryBakery::Error, /:orphan/)
    end

    it 'raises through bake! as well' do
      expect { FactoryBakery.bake!(:unknown_bang) }
        .to raise_error(FactoryBakery::Error, /:unknown_bang/)
    end
  end

  describe 'symbol and class registrations together' do
    it 'coexists and applies last-one-wins per key' do
      model = define_model('CoexistRecord', name: :string)

      FactoryBakery.define(:coexist, klass: model) { name { 'symbol-first' } }
      FactoryBakery.define(model) { name { 'class-first' } }

      expect(FactoryBakery.bake(:coexist).name).to eq('symbol-first')
      expect(FactoryBakery.bake(model).name).to eq('class-first')

      FactoryBakery.define(:coexist, klass: model) { name { 'symbol-second' } }

      expect(FactoryBakery.bake(:coexist).name).to eq('symbol-second')
      expect(FactoryBakery.bake(model).name).to eq('class-first')
    end

    it 'keeps a symbol definition from leaking into a class bake with no class definition' do
      model = define_model('ClassOnlyRecord', name: :string) do
        validates :name, presence: true
      end

      FactoryBakery.define(:class_only, klass: model) { name { 'symbol value' } }

      record = FactoryBakery.bake(model)

      expect(record).to be_a(model)
      expect(record.name).not_to eq('symbol value')
      expect(record).to be_valid
    end
  end

  describe 'traits and overrides through symbol targets' do
    it 'applies traits and call-site overrides identically to class targets' do
      model = define_model('SymbolTraitUser', name: :string, role: :string, city: :string) do
        validates :name, presence: true
      end

      FactoryBakery.define(:symbol_trait_user, klass: model) do
        name { 'base' }
        city { 'base city' }

        trait :admin do
          name { 'admin' }
          role { 'admin' }
        end
      end

      record = FactoryBakery.bake(:symbol_trait_user, :admin, name: 'x', city: 'override city')

      expect(record.name).to eq('x')
      expect(record.role).to eq('admin')
      expect(record.city).to eq('override city')
      expect(record).to be_valid
    end

    it 'persists a symbol-target bake through bake!' do
      model = define_model('SymbolPersistedUser', name: :string) do
        validates :name, presence: true
      end

      FactoryBakery.define(:symbol_persisted_user, klass: model) do
        name { 'persisted symbol' }
      end

      record = FactoryBakery.bake!(:symbol_persisted_user)

      expect(record).to be_persisted
      expect(record.name).to eq('persisted symbol')
    end

    it 'names the symbol in a missing-trait error' do
      model = define_model('SymbolTraitErrorUser', name: :string)

      FactoryBakery.define(:symbol_trait_error_user, klass: model) do
        name { 'base' }
      end

      expect { FactoryBakery.bake(:symbol_trait_error_user, :missing) }
        .to raise_error(FactoryBakery::Error, /:missing/)
    end
  end
end
