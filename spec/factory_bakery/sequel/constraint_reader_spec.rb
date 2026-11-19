# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/sequel_database'

# Mapping of Sequel's STORED validations into the framework-agnostic
# ConstraintSet fields. Sequel stores validations as declarative data only
# under the validation_class_methods plugin (`Model.validation_reflections`);
# validation_helpers runs imperatively inside `validate` and is therefore
# documented as not introspectable (see the plugin's comments and the README).
RSpec.describe 'Sequel mapper constraint reading', :sequel_mapper do
  include DefineSequelModelMacros

  let!(:model) do
    define_sequel_model(
      'SeqValidated',
      name: :string, code: :string, age: :integer, handle: :string,
      status: :string, lucky: :integer, terms: :string, flag: :boolean,
      note: { type: :string, null: false, default: '' }
    ) do
      plugin :validation_class_methods

      validates_presence_of :name
      validates_presence_of :flag
      validates_presence_of :note
      validates_length_of :name, maximum: 40, minimum: 3
      validates_length_of :code, is: 5
      validates_numericality_of :age, only_integer: true
      validates_format_of :handle, with: /\A[a-z0-9_]+\z/
      validates_inclusion_of :status, in: %w[pending done]
      validates_inclusion_of :lucky, in: [3, 7, 11]
      validates_acceptance_of :terms
    end
  end

  def constraints_for(attr_name)
    FactoryBakery::ConstraintSet.for(model, attr_name)
  end

  it 'maps presence reflections to must_be_present' do
    constraints = constraints_for('name')

    expect(constraints.must_be_present).to be(true)
    expect(constraints.value_shaping).to be(true)
    expect(constraints.has_validators).to be(true)
  end

  it 'maps length reflections to the length fields' do
    constraints = constraints_for('name')

    expect(constraints.length_validated).to be(true)
    expect(constraints.min_length).to eq(3)
    expect(constraints.max_length).to eq(40)
  end

  it 'maps an exact length reflection' do
    constraints = constraints_for('code')

    expect(constraints.exact_length).to eq(5)
    expect(constraints.length_validated).to be(true)
  end

  it 'maps numericality reflections with their integer-only option' do
    constraints = constraints_for('age')

    expect(constraints.numericality_validated).to be(true)
    expect(constraints.numericality_only_integer).to be(true)
  end

  it 'maps format reflections to with_regexes' do
    constraints = constraints_for('handle')

    expect(constraints.format_validated).to be(true)
    expect(constraints.with_regexes).to eq([/\A[a-z0-9_]+\z/])
  end

  it 'maps inclusion reflections to allowed_values in their raw form' do
    constraints = constraints_for('status')

    expect(constraints.inclusion_validated).to be(true)
    expect(constraints.allowed_values).to eq(%w[pending done])
    expect(constraints.first_inclusion_values).to eq(%w[pending done])
  end

  it 'maps acceptance reflections to accept_value' do
    constraints = constraints_for('terms')

    expect(constraints.acceptance_validated).to be(true)
    expect(constraints.accept_value).to eq('1')
  end

  it 'generates values that satisfy every mapped reflection' do
    record = FactoryBakery.bake!(model)

    expect(record.name.length).to be_between(3, 40)
    expect(record.code.length).to eq(5)
    expect(record.age).to be_an(Integer)
    expect(record.handle).to match(/\A[a-z0-9_]+\z/)
    expect(%w[pending done]).to include(record.status)
    expect([3, 7, 11]).to include(record.lucky)
    expect(record.terms).to eq('1')
    expect(record.flag).to be(true)
  end

  it 'fills a presence-validated defaulted column instead of keeping the blank default' do
    constraints = constraints_for('note')

    expect(constraints.value_shaping).to be(true)

    record = FactoryBakery.bake(model)
    expect(record.note).not_to be_blank
  end

  describe 'an imperative validation_helpers model' do
    # validation_helpers runs its checks inline inside `Model#validate`: they
    # are code, not stored data, so no mapper can read them as constraints.
    # The documented behavior is a schema-facts fallback, and this spec pins
    # it: nothing is faked about the declarations being invisible.
    let!(:helpers_model) do
      define_sequel_model('SeqHelpers', code: { type: :string, size: 8, null: false }) do
        plugin :validation_helpers

        def validate
          super
          validates_presence :code
          validates_max_length 8, :code
        end
      end
    end

    it 'exposes no stored validations; schema facts still drive generation' do
      constraints = FactoryBakery::ConstraintSet.for(helpers_model, 'code')

      expect(helpers_model).not_to respond_to(:validation_reflections)
      expect(constraints.must_be_present).to be(false)
      expect(constraints.has_validators).to be(false)
      expect(constraints.db_limit).to eq(8)
    end

    it 'still bakes values that satisfy the imperative rules' do
      record = FactoryBakery.bake!(helpers_model)

      expect(record).not_to be_new
      expect(record.code).to be_a(String)
      expect(record.code.length).to be <= 8
    end
  end
end
