# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'enums declared on an alias_attribute' do
  include DefineConstantMacros

  describe 'an alias for an enum column' do
    let!(:history_model) do
      define_model('ReviewableHistory', reviewable_history_type: { type: :integer, null: false }) do
        alias_attribute :kind, :reviewable_history_type
        enum :kind, { created: 0, transitioned: 1, edited: 2 }
      end
    end

    it 'fills the column with a valid enum label' do
      record = FactoryBakery.bake(history_model)

      expect(%w[created transitioned edited]).to include(record.kind)
      expect(record.reviewable_history_type).to eq(record.kind)
    end

    it 'builds and persists a valid record instead of raising ArgumentError' do
      record = FactoryBakery.bake!(history_model)

      expect(record).to be_valid
      expect(history_model.find(record.id).kind).to eq(record.kind)
    end

    it 'still honours a call-site override through either name' do
      expect(FactoryBakery.bake(history_model, kind: 'edited').kind).to eq('edited')
      expect(FactoryBakery.bake(history_model, reviewable_history_type: 'transitioned').kind).to eq('transitioned')
    end

    it 'still honours a factory declaration through either name' do
      FactoryBakery.define(history_model) { kind { 'transitioned' } }

      expect(FactoryBakery.bake(history_model).kind).to eq('transitioned')
    end
  end

  describe 'an enum declared on the column while an alias exists' do
    let!(:status_model) do
      define_model('AliasedStatus', status: { type: :integer, null: false }) do
        alias_attribute :state, :status
        enum :status, { pending: 0, shipped: 1 }
      end
    end

    it 'fills the column with a valid enum label readable through the alias' do
      record = FactoryBakery.bake(status_model)

      expect(%w[pending shipped]).to include(record.state)
    end
  end

  describe 'an alias named type pointing at a non-inheritance column' do
    let!(:history_model) do
      define_model('TypeHistory', reviewable_history_type: { type: :integer, null: false }) do
        alias_attribute :type, :reviewable_history_type
        enum :type, { created: 0, transitioned: 1, edited: 2 }
      end
    end

    it 'fills the aliased column instead of guarding it as the STI discriminator' do
      record = FactoryBakery.bake(history_model)

      expect(%w[created transitioned edited]).to include(record.type)
      expect(record.reviewable_history_type).to eq(record.type)
    end
  end

  describe 'STI with an alias present' do
    let!(:vehicle_model) do
      define_model('Vehicle', type: :string, kind_code: :integer) do
        alias_attribute :kind, :kind_code
        enum :kind, { car: 0, truck: 1 }
      end
    end

    before do
      define_class('Car', vehicle_model)
    end

    it 'preserves the real discriminator while filling the aliased enum column' do
      record = FactoryBakery.bake(Car, fill_optional: true)

      expect(record.type).to eq(Car.sti_name)
      expect(%w[car truck]).to include(record.kind)
    end
  end
end
