# frozen_string_literal: true

require 'spec_helper'
require 'active_model'

RSpec.describe 'presence semantics (issue #34)' do
  include DefineConstantMacros

  describe 'boolean column with presence: true' do
    let!(:model) do
      define_model('PresentFlag', published: :boolean) do
        validates :published, presence: true
      end
    end

    it 'bakes a truthy boolean on every draw (audit 20x probe)' do
      records = 20.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:published)).to all(eq(true))
      expect(records).to all(be_valid)
    end

    it 'persists every bake with bake!' do
      records = 20.times.map { FactoryBakery.bake!(model) }

      expect(records).to all(be_persisted)
      expect(records.map(&:published)).to all(eq(true))
    end
  end

  describe 'presence validator class paths' do
    it 'recognises the ActiveRecord wrapper installed by validates :presence' do
      model = define_model('ArPresenceFlag', flag: :boolean) do
        validates :flag, presence: true
      end

      expect(model.validators_on(:flag).map(&:class)).to include(ActiveRecord::Validations::PresenceValidator)
      expect(FactoryBakery.bake(model).flag).to be(true)
    end

    it 'recognises an ActiveModel presence validator on an ActiveRecord target' do
      model = define_model('AmPresenceFlag', flag: :boolean)
      model.validates_with ActiveModel::Validations::PresenceValidator, attributes: [:flag]

      expect(model.validators_on(:flag).map(&:class)).to include(ActiveModel::Validations::PresenceValidator)
      expect(FactoryBakery.bake(model).flag).to be(true)
    end
  end

  describe 'a column with a database default and presence: true' do
    it 'generates a value when the database default is blank' do
      model = define_model('BlankDefaultPresent', status: { type: :string, default: '' }) do
        validates :status, presence: true
      end

      records = 20.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:status)).to all(be_present)
      expect(records).to all(be_valid)
    end

    it 'generates a value instead of leaving the non-blank default untouched' do
      model = define_model('DraftDefaultPresent', status: { type: :string, default: 'draft' }) do
        validates :status, presence: true
      end
      allow(FFaker::Lorem).to receive(:word).and_return('generated')

      record = FactoryBakery.bake(model, fill_optional: true)

      expect(record.status).to eq('generated')
      expect(record).to be_valid
    end

    it 'generates true for a boolean column defaulted to false' do
      model = define_model('FalseDefaultPresent', flag: { type: :boolean, default: false }) do
        validates :flag, presence: true
      end

      records = 20.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:flag)).to all(eq(true))
      expect(records).to all(be_valid)
    end
  end

  describe 'PORO presence validation' do
    let(:base) do
      Class.new do
        include ActiveModel::Model
        include ActiveModel::Validations
      end
    end

    let!(:model) do
      define_class('PresencePoro', base) do
        attr_accessor :name

        validates :name, presence: true
      end
    end

    it 'still fills a present value and stays valid on every bake' do
      records = 20.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:name)).to all(be_present)
      expect(records).to all(be_valid)
    end
  end

  describe 'absence validation' do
    it 'still emits nil' do
      model = define_model('AbsentFlag', flag: :boolean) do
        validates :flag, absence: true
      end

      record = FactoryBakery.bake(model)

      expect(record.flag).to be_nil
      expect(record).to be_valid
    end

    it 'takes precedence over presence when both validators are present' do
      model = define_model('AbsentPresentFlag', flag: :boolean) do
        validates :flag, absence: true
        validates :flag, presence: true
      end

      expect(FactoryBakery.bake(model).flag).to be_nil
    end
  end
end
