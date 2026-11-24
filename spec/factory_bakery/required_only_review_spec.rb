# frozen_string_literal: true

require 'spec_helper'
require 'factory_bakery/associations'
require_relative 'sequel/support/sequel_database'

# Verified findings from the required-only review: nullable validators that
# reject nil, Sequel's imperative validation, verification scope, the fallback
# savepoint, and bounded condition evaluation. Every example goes through the
# public bake/bake! API on models defined in this file.
RSpec.describe 'required-only review fixes' do
  include DefineConstantMacros

  after { FactoryBakery.fill_optional = false }

  describe 'nil-rejecting validators on nullable columns' do
    it 'bakes a nullable uniqueness column twice with bake! and no fill_optional' do
      model = define_model('ReviewUniqueCode', code: :string) do
        validates :code, uniqueness: true
      end
      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'alpha', 'beta')

      first = FactoryBakery.bake!(model)
      second = FactoryBakery.bake!(model)

      expect(first.code).to eq('alpha')
      expect(second.code).to eq('beta')
      expect([first, second]).to all(be_persisted)
      expect([first, second]).to all(be_valid)
      expect(model.count).to eq(2)
    end

    it 'leaves a nullable uniqueness column nil when the validator allows nil' do
      model = define_model('ReviewOptionalUniqueCode', code: :string) do
        validates :code, uniqueness: true, allow_nil: true
      end

      expect(FactoryBakery.bake(model).code).to be_nil
    end

    it 'fills a nullable comparison column so the record is valid' do
      model = define_model('ReviewComparisonSpan', starts_at: :datetime, ends_at: :datetime) do
        validates :ends_at, comparison: { greater_than: :starts_at }
      end

      record = FactoryBakery.bake(model)

      expect(record.ends_at).not_to be_nil
      expect(record).to be_valid
      expect(FactoryBakery.bake!(model)).to be_persisted
    end

    it 'leaves a nullable comparison column nil when the validator allows nil' do
      model = define_model('ReviewOptionalComparisonSpan', starts_at: :datetime, ends_at: :datetime) do
        validates :ends_at, comparison: { greater_than: :starts_at }, allow_nil: true
      end

      expect(FactoryBakery.bake(model).ends_at).to be_nil
    end
  end

  describe 'verification scope' do
    it 'does not run valid? for a plain model with a has_many' do
      validations = 0
      child = define_model('ReviewPlainChild', owner_id: :integer)
      parent = define_model('ReviewPlainParent', name: :string) do
        has_many :review_plain_children, foreign_key: :owner_id
        before_validation { validations += 1 }
      end

      record = FactoryBakery.bake(parent)

      expect(record).to be_a(parent)
      expect(validations).to eq(0)
      # The callback is real: a deliberate validation does fire it.
      record.valid?
      expect(validations).to eq(1)
      expect(child.count).to eq(0)
    end

    it 'verifies a model whose validation logic is not introspectable' do
      validations = 0
      validator = Class.new(ActiveModel::Validator) do
        define_method(:validate) { |_record| validations += 1 }
      end
      model = define_model('ReviewCustomValidated', token: :string, secret: :string) do
        validates_with validator
      end

      FactoryBakery.bake(model)

      expect(validations).to eq(1)
    end
  end

  describe 'verified fallback savepoint' do
    let(:credential_validator) do
      Class.new(ActiveModel::Validator) do
        def validate(record)
          return unless record.token.nil? && record.secret.nil?

          record.errors.add(:base, 'a credential must be selected')
        end
      end
    end

    it 'leaves one parent row when a declaration block bakes the parent', :savepoints do
      validator = credential_validator
      parent = define_model('ReviewDeclParent', name: :string)
      child = define_model('ReviewDeclChild', token: :string, secret: :string) do
        attr_accessor :parent

        validates_with validator
      end
      FactoryBakery.define(child) { parent { FactoryBakery.bake!(parent) } }

      record = FactoryBakery.bake!(child)

      expect(record).to be_persisted
      expect(record.parent).to be_a(parent)
      expect(parent.count).to eq(1)
    end

    context 'with the associations plugin active' do
      before do
        FactoryBakery.reset_plugins!
        FactoryBakery.register_plugin(FactoryBakery::Associations::Plugin)
        FactoryBakery::Associations.reset_configuration!
      end

      after do
        FactoryBakery.reset_plugins!
        FactoryBakery::Associations.reset_configuration!
      end

      it 'leaves one parent row when the FK column carries the presence validator', :savepoints do
        validator = credential_validator
        parent = define_model('ReviewFkParent', name: :string)
        child = define_model('ReviewFkChild', owner_id: :integer, token: :string, secret: :string) do
          belongs_to :owner, class_name: 'ReviewFkParent', optional: true
          validates :owner_id, presence: true
          validates_with validator
        end

        record = FactoryBakery.bake!(child)

        expect(record).to be_persisted
        expect(record.owner).to be_persisted
        expect(parent.count).to eq(1)
      end
    end
  end

  describe 'bounded condition evaluation' do
    it 'evaluates a conditional validator at most twice for one bake' do
      calls = 0
      condition = lambda do
        calls += 1
        true
      end
      model = define_model('ReviewBoundedCondition', code: :string) do
        validates :code, format: { with: /\A[a-z]+\z/ }, if: condition
      end

      record = FactoryBakery.bake(model)

      expect(record.code).to match(/\A[a-z]+\z/)
      expect(calls).to be <= 2
    end

    it 're-evaluates once per bake instead of leaking the cached result' do
      calls = 0
      condition = lambda do
        calls += 1
        true
      end
      model = define_model('ReviewPerBakeCondition', code: :string) do
        validates :code, format: { with: /\A[a-z]+\z/ }, if: condition
      end

      FactoryBakery.bake(model)
      FactoryBakery.bake(model)

      expect(calls).to be <= 4
      expect(calls).to be >= 2
    end
  end

  describe 'Sequel validation_helpers', :sequel_mapper do
    include DefineSequelModelMacros

    it 'verifies an imperative validate method and fills the column it needs' do
      model = define_sequel_model('ReviewSeqPresence', name: :string, note: :string) do
        plugin :validation_helpers

        def validate
          super
          validates_presence :name
        end
      end

      record = FactoryBakery.bake(model)

      expect(record.name).to be_present
      expect(record).to be_valid
    end
  end
end
