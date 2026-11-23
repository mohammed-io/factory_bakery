# frozen_string_literal: true

require 'spec_helper'
require 'active_support/notifications'

# The root record of a bake! leaves its database uniqueness check to the save
# that follows, and regenerates a generated value the save finds taken. What
# must not change: the bake still ends with a unique, saved record, and a value
# the caller chose is never replaced.
RSpec.describe 'uniqueness deferred to the bake! save' do
  include DefineConstantMacros

  def selects_in
    statements = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      statements << payload[:sql] if payload[:sql].start_with?('SELECT') && payload[:name] != 'SCHEMA'
    end
    yield
    statements
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  describe 'a plain unique column' do
    let!(:model) do
      define_model('DeferredCode', code: :string) do
        validates :code, uniqueness: true
      end
    end

    it 'asks the database once, in the save, not also while building' do
      expect(selects_in { FactoryBakery.bake!(model) }.size).to eq(1)
    end

    it 'regenerates a generated value the save finds taken, and saves the new one' do
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

    it 'still explains a failure that has nothing to do with uniqueness' do
      model.validates :code, length: { maximum: 3 }

      expect { FactoryBakery.bake!(model, code: 'toolong') }
        .to raise_error(ActiveRecord::RecordInvalid, /FactoryBakery could not produce a valid/)
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

  describe 'a column the save may not validate' do
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

  describe 'deferral is limited to plain validators' do
    it 'does not defer an allow_blank validator, so a blank collision is regenerated instead of hitting the index' do
      model = define_model('DeferredAllowBlank', code: :string) do
        validates :code, uniqueness: { allow_blank: true }
      end
      model.connection.add_index(model.table_name, :code, unique: true)
      model.create!(code: '')
      allow(FFaker::Lorem).to receive(:word).and_return('', 'zeta')

      record = FactoryBakery.bake!(model, fill_optional: true)

      expect(record.code).to eq('zeta')
      expect(record).to be_persisted
      expect(model.pluck(:code)).to contain_exactly('', 'zeta')
    end

    it 'does not defer an except_on validator, so a taken value is regenerated while building' do
      model = define_model('DeferredExceptOn', code: :string) do
        validates :code, uniqueness: { except_on: :create }
      end
      model.connection.add_index(model.table_name, :code, unique: true)
      model.create!(code: 'alpha')
      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'beta')

      record = FactoryBakery.bake!(model, fill_optional: true)

      expect(record.code).to eq('beta')
      expect(model.pluck(:code)).to contain_exactly('alpha', 'beta')
    end

    it 'does not defer when one of two validators is conditional, and regenerates at build time' do
      model = define_model('DeferredDualValidators', code: :string, kind: :string) do
        validates :code, uniqueness: { if: -> { false } }
        validates :code, uniqueness: { scope: :kind }
      end
      model.connection.add_index(model.table_name, :code, unique: true)
      model.create!(code: 'alpha', kind: 'held')
      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'beta')

      record = FactoryBakery.bake!(model, fill_optional: true)

      expect(record.code).to eq('beta')
      expect(model.pluck(:code)).to contain_exactly('alpha', 'beta')
    end

    it 'does not defer a strict validator, so bake! returns the regenerated value instead of raising' do
      model = define_model('DeferredStrict', code: :string) do
        validates! :code, uniqueness: true
      end
      model.create!(code: 'alpha')
      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'beta')

      expect(FactoryBakery.bake!(model, fill_optional: true).code).to eq('beta')
    end
  end

  describe 'the retry after a failed save' do
    it 'propagates an exception an after_create raises, without swallowing or retrying it' do
      model = define_model('DeferredCallbackBoom', code: :string) do
        validates :code, uniqueness: true
      end
      booms = 0
      model.class_eval do
        after_create do
          booms += 1
          errors.add(:code, :taken)
          raise IOError, 'boom'
        end
      end
      allow(FFaker::Lorem).to receive(:word).and_return('word')

      expect { FactoryBakery.bake!(model, fill_optional: true) }.to raise_error(IOError, /boom/)
      expect(booms).to eq(1)
    end

    it 'stops retrying when a before_validation keeps rewriting the value back to a taken one' do
      model = define_model('DeferredNoProgress', code: :string) do
        validates :code, uniqueness: true
      end
      model.create!(code: 'fixed')
      runs = 0
      model.before_validation do
        runs += 1
        self.code = 'fixed'
      end
      allow(FFaker::Lorem).to receive(:word).and_return('hello')

      expect { FactoryBakery.bake!(model, fill_optional: true) }
        .to raise_error(ActiveRecord::RecordInvalid, /taken/)
      expect(runs).to be <= 2
    end

    it 'never retries a taken error on an attribute that was not deferred' do
      model = define_model('DeferredCustomTaken', slug: { type: :string, null: false })
      passes = 0
      model.validate do
        passes += 1
        errors.add(:slug, :taken)
      end

      expect { FactoryBakery.bake!(model) }.to raise_error(ActiveRecord::RecordInvalid, /taken/)
      expect(passes).to eq(1)
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
