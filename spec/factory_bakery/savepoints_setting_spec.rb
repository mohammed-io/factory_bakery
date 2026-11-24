# frozen_string_literal: true

require 'spec_helper'

# `FactoryBakery.savepoints` decides whether the gem wraps the `bake!`
# envelope and the verified fallback's attempts in a nested transaction. Off
# (the default) behaves like factory_bot for `bake!`: nothing its own save
# rolls back is undone, and rows a discarded lean fallback attempt wrote stay
# behind. On, a failed bake! leaves no rows and the rebuild leaves one copy
# of what a declaration block saved (ADR-0006). The associations plugin's
# best-effort edges keep their savepoints either way.
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

    it 'leaves the lean attempt\'s parent row behind by default' do
      account, owner = fallback_models

      expect(FactoryBakery.bake(owner)).to be_valid

      expect(account.count).to eq(2)
    end

    it 'leaves one parent row when savepoints are on', :savepoints do
      account, owner = fallback_models

      expect(FactoryBakery.bake(owner)).to be_valid

      expect(account.count).to eq(1)
    end

    it 'raises on the rebuild of a declaration that bakes a unique parent by default' do
      # The declaration block runs in the lean attempt and again in the
      # rebuild. Without the fallback's own savepoint, the rebuild's
      # `bake!` of the same unique name fails with "has already been
      # taken" against the row the lean attempt left behind. The
      # documented fix is `FactoryBakery.savepoints = true`.
      account = define_model('SpFbUniqueAccount', name: :string) do
        validates :name, uniqueness: true
      end
      owner = define_model('SpFbUniqueOwner', name: :string, nickname: :string, account_id: :integer) do
        belongs_to :account, class_name: 'SpFbUniqueAccount', optional: true
        validate { errors.add(:nickname, :blank) if nickname.blank? }
      end
      FactoryBakery.define(owner) { account { FactoryBakery.bake!(account, name: 'acme') } }

      expect { FactoryBakery.bake(owner) }.to raise_error(ActiveRecord::RecordInvalid, /taken/)
    end

    it 'succeeds with one acme row when savepoints are on', :savepoints do
      account = define_model('SpFbUniqueAccountOn', name: :string) do
        validates :name, uniqueness: true
      end
      owner = define_model('SpFbUniqueOwnerOn', name: :string, nickname: :string, account_id: :integer) do
        belongs_to :account, class_name: 'SpFbUniqueAccountOn', optional: true
        validate { errors.add(:nickname, :blank) if nickname.blank? }
      end
      FactoryBakery.define(owner) { account { FactoryBakery.bake!(account, name: 'acme') } }

      baked = FactoryBakery.bake(owner)

      expect(baked).to be_valid
      expect(account.where(name: 'acme').count).to eq(1)
    end
  end

  it 'still bakes and saves a plain record with savepoints off' do
    plain = define_model('SpPlain', name: :string) { validates :name, presence: true }

    expect(FactoryBakery.bake!(plain)).to be_persisted
  end
end
