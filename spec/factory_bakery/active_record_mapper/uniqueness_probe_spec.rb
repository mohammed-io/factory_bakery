# frozen_string_literal: true

require 'spec_helper'
require 'factory_bakery/active_record_mapper/uniqueness_probe'

# The per-column database check behind the mapper's `uniqueness_check`,
# exercised directly through observable behavior: the model's own uniqueness
# validator decides against a probe of the record, or the table itself when
# only a unique index guards the column.
RSpec.describe FactoryBakery::ActiveRecordMapper::UniquenessProbe do
  include DefineConstantMacros

  def validators_for(model, attr_name)
    FactoryBakery::ActiveRecordMapper::Mapper.new.send(:uniqueness_validators_for, model, attr_name)
  end

  describe '.taken? with a plain uniqueness validator' do
    let!(:model) do
      define_model('ProbeWidget', code: :string) do
        validates :code, uniqueness: true
      end
    end

    before { model.create!(code: 'alpha') }

    it 'is true when the value exists' do
      expect(described_class.taken?(model.new, 'code', 'alpha', validators_for(model, 'code'))).to be(true)
    end

    it 'is false when the value is free' do
      expect(described_class.taken?(model.new, 'code', 'beta', validators_for(model, 'code'))).to be(false)
    end
  end

  describe '.taken? with a column guarded only by a unique index' do
    let!(:model) do
      define_model('ProbeIndexedThing', code: { type: :string, index: { unique: true } })
    end

    before { model.create!(code: 'alpha') }

    it 'is true for a value the table holds' do
      expect(described_class.taken?(model.new, 'code', 'alpha', [])).to be(true)
    end

    it 'is false for a value the table does not hold' do
      expect(described_class.taken?(model.new, 'code', 'beta', [])).to be(false)
    end
  end

  describe '.taken? with a scoped uniqueness validator' do
    let!(:model) do
      define_model('ProbeScopedGadget', code: :string, kind: :string) do
        validates :code, uniqueness: { scope: :kind }
      end
    end

    before { model.create!(code: 'alpha', kind: 'letter') }

    it 'is true within the same scope' do
      record = model.new(code: 'alpha', kind: 'letter')
      expect(described_class.taken?(record, 'code', 'alpha', validators_for(model, 'code'))).to be(true)
    end

    it 'is false in another scope' do
      record = model.new(code: 'alpha', kind: 'digit')
      expect(described_class.taken?(record, 'code', 'alpha', validators_for(model, 'code'))).to be(false)
    end
  end
end
