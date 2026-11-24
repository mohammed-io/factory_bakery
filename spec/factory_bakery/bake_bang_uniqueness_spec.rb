# frozen_string_literal: true

require 'spec_helper'

# The build-time uniqueness check is eager for every record, including the root
# of a bake!: a generated value an existing row holds is regenerated before
# anything is saved, while a value the caller chose is never replaced.
RSpec.describe 'uniqueness of a bake! root' do
  include DefineConstantMacros

  describe 'a plain unique column' do
    let!(:model) do
      define_model('DeferredCode', code: :string) do
        validates :code, uniqueness: true
      end
    end

    it 'regenerates a generated value an existing row holds, and saves the new one' do
      model.create!(code: 'alpha')
      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'beta')

      record = FactoryBakery.bake!(model, fill_optional: true)

      expect(record.code).to eq('beta')
      expect(record).to be_persisted
      expect(model.pluck(:code)).to contain_exactly('alpha', 'beta')
    end

    it 'never replaces a value the caller chose: the taken override still fails the save' do
      model.create!(code: 'chosen')

      expect { FactoryBakery.bake!(model, code: 'chosen') }.to raise_error(ActiveRecord::RecordInvalid, /taken/)
    end

    it 'raises the contextual error when no free value can be generated' do
      only_one = define_model('DeferredOnlyOne', code: :string) do
        validates :code, uniqueness: true, inclusion: { in: %w[only] }
      end
      only_one.create!(code: 'only')

      expect { FactoryBakery.bake!(only_one) }
        .to raise_error(FactoryBakery::Error, /could not generate a unique value/)
    end

    it 'keeps asking the database while building for a plain bake (nothing saves it)' do
      model.create!(code: 'alpha')
      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'beta')

      expect(FactoryBakery.bake(model, fill_optional: true).code).to eq('beta')
    end
  end

  describe 'columns the save may not validate' do
    it 'still checks a conditional validator while building, so a taken value never reaches the database' do
      model = define_model('DeferredConditional', code: :string, check: :boolean) do
        validates :code, uniqueness: true, if: :check
      end
      model.connection.add_index(model.table_name, :code, unique: true)
      model.create!(code: 'alpha')
      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'beta')

      record = FactoryBakery.bake!(model, fill_optional: true, check: false)

      expect(record.code).to eq('beta')
    end

    it 'still checks a column protected only by a unique index while building' do
      model = define_model('DeferredIndexOnly', code: :string)
      model.connection.add_index(model.table_name, :code, unique: true)
      model.create!(code: 'alpha')
      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'beta')

      record = FactoryBakery.bake!(model, fill_optional: true)

      expect(record.code).to eq('beta')
    end
  end

  describe 'nested bakes' do
    it 'checks a parent baked from a declaration block while building' do
      account = define_model('DeferredAccount', code: :string) { validates :code, uniqueness: true }
      owner = define_model('DeferredOwner', label: :string, account_id: :integer) do
        belongs_to :account, class_name: 'DeferredAccount', optional: true
      end
      account.create!(code: 'alpha')
      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'beta')
      FactoryBakery.define(owner) { account { FactoryBakery.bake(account, fill_optional: true) } }

      expect(FactoryBakery.bake!(owner).account.code).to eq('beta')
    end
  end
end
