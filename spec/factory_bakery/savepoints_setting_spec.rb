# frozen_string_literal: true

require 'spec_helper'

# `FactoryBakery.savepoints` decides whether the gem wraps its own attempts in a
# nested transaction. Off (the default) behaves like factory_bot: nothing the
# gem does is undone. On, a failed bake! leaves no rows (ADR-0006).
RSpec.describe 'FactoryBakery.savepoints' do
  include DefineConstantMacros

  def models
    account = define_model('SpAccount', name: :string)
    user = define_model('SpUser', name: :string, account_id: :integer) do
      belongs_to :account, class_name: 'SpAccount', optional: true
      validates :name, absence: true
    end
    FactoryBakery.define(user) { account { FactoryBakery.bake!(account) } }
    [account, user]
  end

  after { FactoryBakery.savepoints = false }

  it 'is off by default' do
    expect(FactoryBakery.savepoints?).to be(false)
  end

  it 'is set through savepoints= and configure' do
    FactoryBakery.configure { |config| config.savepoints = true }
    expect(FactoryBakery.savepoints?).to be(true)

    FactoryBakery.savepoints = nil
    expect(FactoryBakery.savepoints?).to be(false)
  end

  context 'when a bake! fails after a nested bake! already saved a parent' do
    it 'keeps the parent row by default, as factory_bot does' do
      account, user = models

      expect { FactoryBakery.bake!(user, name: 'invalid') }.to raise_error(ActiveRecord::RecordInvalid)

      expect(account.count).to eq(1)
      expect(user.count).to eq(0)
    end

    it 'rolls everything back when savepoints are on' do
      account, user = models
      FactoryBakery.savepoints = true

      expect { FactoryBakery.bake!(user, name: 'invalid') }.to raise_error(ActiveRecord::RecordInvalid)

      expect(account.count).to eq(0)
      expect(user.count).to eq(0)
    end
  end

  context 'when the verified fallback rebuilds a record whose declaration saved a parent' do
    def fallback_models
      account = define_model('SpFbAccount', name: :string)
      owner = define_model('SpFbOwner', name: :string, nickname: :string, account_id: :integer) do
        belongs_to :account, class_name: 'SpFbAccount', optional: true
        validate { errors.add(:nickname, :blank) if nickname.blank? }
      end
      FactoryBakery.define(owner) { account { FactoryBakery.bake!(account) } }
      [account, owner]
    end

    it 'leaves the first attempt\'s parent behind by default' do
      account, owner = fallback_models

      expect(FactoryBakery.bake(owner)).to be_valid

      expect(account.count).to eq(2)
    end

    it 'leaves one parent row when savepoints are on' do
      account, owner = fallback_models
      FactoryBakery.savepoints = true

      expect(FactoryBakery.bake(owner)).to be_valid

      expect(account.count).to eq(1)
    end
  end

  it 'still bakes and saves a plain record with savepoints off' do
    plain = define_model('SpPlain', name: :string) { validates :name, presence: true }

    expect(FactoryBakery.bake!(plain)).to be_persisted
  end
end
