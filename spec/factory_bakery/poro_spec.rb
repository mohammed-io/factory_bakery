# frozen_string_literal: true

require 'spec_helper'
require 'active_model'

RSpec.describe 'FactoryBakery PORO targets' do
  include DefineConstantMacros

  describe 'a plain class with setters and no ActiveModel/ActiveRecord' do
    let(:model) do
      define_class('PlainPerson') do
        attr_accessor :name, :age, :city
      end
    end

    it 'sets declared attributes and call-site overrides through setters without raising' do
      FactoryBakery.define(model) do
        name { 'from factory' }
      end

      record = FactoryBakery.bake(model, age: 42)

      expect(record).to be_a(model)
      expect(record.name).to eq('from factory')
      expect(record.age).to eq(42)
      expect(record.city).to be_nil
    end

    it 'leaves every attribute nil when there are no declarations, overrides or validators' do
      record = FactoryBakery.bake(model)

      expect(record.name).to be_nil
      expect(record.age).to be_nil
      expect(record.city).to be_nil
    end

    it 'never calls columns_hash on a plain class' do
      expect(model).not_to respond_to(:columns_hash)
      expect { FactoryBakery.bake(model, name: 'x') }.not_to raise_error
    end

    it 'returns the baked object from bake! without attempting persistence' do
      record = FactoryBakery.bake!(model, name: 'baked')

      expect(record).to be_a(model)
      expect(record.name).to eq('baked')
      expect(record).not_to respond_to(:save!)
    end
  end

  describe 'an ActiveModel-compatible class with validators and no table' do
    let(:base) do
      Class.new do
        include ActiveModel::Model
        include ActiveModel::Validations
      end
    end

    let(:model) do
      define_class('ValidatedPerson', base) do
        attr_accessor :status, :code, :age, :score, :email, :email_confirmation, :terms, :untouched

        validates :status, inclusion: { in: %w[pending completed] }
        validates :code, length: { is: 5 }
        validates :age, numericality: { greater_than: 18, less_than: 65, only_integer: true }
        validates :score, numericality: { in: 1.0..10.0 }
        validates :email, confirmation: true
        validates :terms, acceptance: { accept: 'yes' }
      end
    end

    it 'fills undeclared validator-covered attributes and leaves unvalidated ones nil' do
      record = FactoryBakery.bake(model)

      expect(%w[pending completed]).to include(record.status)
      expect(record.code.length).to eq(5)
      expect(record.age).to be_between(19, 64).inclusive
      expect(record.score).to be_between(1.0, 10.0).inclusive
      expect(record.email).not_to be_empty
      expect(record.email_confirmation).to eq(record.email)
      expect(record.terms).to eq('yes')
      expect(record.untouched).to be_nil
      expect(record).to be_valid
    end

    it 'still fills validator-covered attributes when call-site overrides are given' do
      record = FactoryBakery.bake(model, status: 'completed')

      expect(record.status).to eq('completed')
      expect(record.code.length).to eq(5)
      expect(record.age).to be_between(19, 64).inclusive
      expect(record).to be_valid
    end

    it 'propagates an overridden confirmation source to its confirmation attribute' do
      record = FactoryBakery.bake(model, email: 'known@example.com')

      expect(record.email).to eq('known@example.com')
      expect(record.email_confirmation).to eq('known@example.com')
    end

    it 'lets an explicit confirmation override win' do
      record = FactoryBakery.bake(model, email: 'a@b.c', email_confirmation: 'explicit@b.c')

      expect(record.email).to eq('a@b.c')
      expect(record.email_confirmation).to eq('explicit@b.c')
    end
  end

  describe 'factory definitions on PORO targets' do
    let(:model) do
      define_class('FactoryPerson') do
        attr_accessor :name, :role, :city
      end
    end

    it 'applies declarations, traits and call-site overrides with the same precedence as AR targets' do
      FactoryBakery.define(model) do
        name { 'base' }
        city { 'base city' }

        trait :admin do
          name { 'admin' }
          role { 'admin' }
        end
      end

      record = FactoryBakery.bake(model, :admin, name: 'call site')

      expect(record.name).to eq('call site')
      expect(record.role).to eq('admin')
      expect(record.city).to eq('base city')
    end

    it 'supports initialize_with through setters when the constructor takes no arguments' do
      FactoryBakery.define(model) do
        initialize_with(name: 'from constructor')
      end

      record = FactoryBakery.bake(model)

      expect(record.name).to eq('from constructor')
    end

    it 'supports initialize_with when the PORO constructor takes keywords' do
      keyword_model = define_class('KeywordPerson') do
        attr_reader :name

        def initialize(name:)
          @name = name
        end
      end

      FactoryBakery.define(keyword_model) do
        initialize_with(name: 'from keyword constructor')
      end

      expect(FactoryBakery.bake(keyword_model).name).to eq('from keyword constructor')
    end

    it 'registers and bakes a symbol factory bound to a PORO via klass:' do
      FactoryBakery.define(:factory_person, klass: model) do
        name { 'symbol name' }

        trait :vip do
          role { 'vip' }
        end
      end

      record = FactoryBakery.bake(:factory_person, :vip, name: 'override')

      expect(record).to be_a(model)
      expect(record.name).to eq('override')
      expect(record.role).to eq('vip')
    end
  end
end
