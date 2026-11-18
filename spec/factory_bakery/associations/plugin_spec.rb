# frozen_string_literal: true

require 'spec_helper'
require 'active_support/notifications'
require 'factory_bakery/associations'

# Public-API behavior of the opt-in associations plugin (A9). Every assertion
# goes through define/bake/bake! or the plugin's mode accessor; builder
# internals are deliberately out of scope.
RSpec.describe 'FactoryBakery associations plugin' do
  before do
    FactoryBakery.reset_plugins!
    FactoryBakery.register_plugin(FactoryBakery::Associations::Plugin)
  end

  after do
    FactoryBakery.reset_plugins!
    FactoryBakery::Associations.mode = :required_only
  end

  # Counts SQL INSERTs through a public notification, the same observable
  # signal the core persistence contract uses.
  def inserts_in
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, _start, _finish, _id, payload|
      count += 1 if payload[:sql].start_with?('INSERT')
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  def define_account_and_user(user_name)
    account = define_model("#{user_name}Account", name: :string)
    user = define_model(user_name, name: :string, account_id: :integer) do
      belongs_to :account, class_name: "#{user_name}Account", optional: false
    end
    [account, user]
  end

  describe 'loading and configuration' do
    it 'tolerates being required twice' do
      expect { require 'factory_bakery/associations' }.not_to raise_error

      account_model, user_model = define_account_and_user('AssocRequireTwiceUser')
      FactoryBakery.define(user_model) { association :account }

      expect(FactoryBakery.bake(user_model).account).to be_a(account_model)
    end

    it 'defaults to :required_only and accepts the three documented modes' do
      expect(FactoryBakery::Associations.mode).to eq(:required_only)

      %i[none required_only all].each do |mode|
        FactoryBakery::Associations.mode = mode
        expect(FactoryBakery::Associations.mode).to eq(mode)
      end
    end

    it 'rejects any other mode with ArgumentError' do
      expect { FactoryBakery::Associations.mode = :sometimes }
        .to raise_error(ArgumentError, /sometimes/)
    end

    it 'leaves core behavior in place when the plugin is not registered' do
      FactoryBakery.reset_plugins!
      user_model = define_model('AssocNoPluginUser', name: :string)
      FactoryBakery.define(user_model) { association :account }

      expect { FactoryBakery.bake(user_model) }.to raise_error(
        FactoryBakery::Error,
        %r{requires the associations plugin: require 'factory_bakery/associations'}
      )
    end

    it 'returns to core behavior when the plugin is unregistered' do
      account_model, user_model = define_account_and_user('AssocUnregisterUser')
      FactoryBakery.define(user_model) { association :account }
      expect(FactoryBakery.bake(user_model).account).to be_a(account_model)

      FactoryBakery.unregister_plugin(FactoryBakery::Associations::Plugin)

      expect { FactoryBakery.bake(user_model) }
        .to raise_error(FactoryBakery::Error, /requires the associations plugin/)
    end
  end

  describe 'bare association on belongs_to' do
    it 'builds the parent unsaved with zero INSERTs, using its registered factory' do
      account_model, user_model = define_account_and_user('AssocUnsavedUser')
      FactoryBakery.define(account_model) { name { 'from parent factory' } }
      FactoryBakery.define(user_model) { association :account }

      user = nil
      inserts = inserts_in { user = FactoryBakery.bake(user_model) }

      expect(inserts).to eq(0)
      expect(user.account).to be_a(account_model)
      expect(user.account.name).to eq('from parent factory')
      expect(user.account).to be_new_record
      expect(account_model.count).to eq(0)
    end

    it 'applies the parent heuristics when no parent factory is registered' do
      _account_model, user_model = define_account_and_user('AssocHeuristicUser')
      FactoryBakery.define(user_model) { association :account }

      expect(FactoryBakery.bake(user_model).account.name).to be_a(String)
    end

    it 'persists owner and parent together under bake!' do
      account_model, user_model = define_account_and_user('AssocBangUser')
      FactoryBakery.define(user_model) { association :account }

      user = FactoryBakery.bake!(user_model)

      expect([user.persisted?, user.account.persisted?, user.account_id == user.account.id])
        .to eq([true, true, true])
      expect(user_model.count).to eq(1)
      expect(account_model.count).to eq(1)
    end

    it 'leaves no parent row when the root save! fails' do
      account_model, user_model = define_account_and_user('AssocRollbackUser')
      user_model.validates :name, absence: true
      FactoryBakery.define(user_model) { association :account }

      expect { FactoryBakery.bake!(user_model, name: 'invalid') }
        .to raise_error(ActiveRecord::RecordInvalid)

      expect(user_model.count).to eq(0)
      expect(account_model.count).to eq(0)
    end

    it 'raises at bake time when the association name does not exist' do
      _account_model, user_model = define_account_and_user('AssocTypoUser')
      FactoryBakery.define(user_model) { association :acount }

      expect { FactoryBakery.bake(user_model) }
        .to raise_error(FactoryBakery::Error, /AssocTypoUser has no association :acount/)
    end

    it 'does not build when the call site supplies the association object' do
      account_model, user_model = define_account_and_user('AssocObjectOverrideUser')
      builds = 0
      FactoryBakery.define(account_model) do
        name do
          builds += 1
          'built'
        end
      end
      FactoryBakery.define(user_model) { association :account }
      account = account_model.create!(name: 'existing')

      expect(FactoryBakery.bake(user_model, account: account).account).to equal(account)
      expect(builds).to eq(0)
      expect(account_model.count).to eq(1)
    end

    it 'does not build when the call site supplies the foreign key' do
      account_model, user_model = define_account_and_user('AssocFkOverrideUser')
      builds = 0
      FactoryBakery.define(account_model) do
        name do
          builds += 1
          'built'
        end
      end
      FactoryBakery.define(user_model) { association :account }
      account = account_model.create!(name: 'existing')

      expect(FactoryBakery.bake(user_model, account_id: account.id).account_id).to eq(account.id)
      expect(builds).to eq(0)
      expect(account_model.count).to eq(1)
    end

    it 'lets a trait assigning nil opt out of the declaration' do
      account_model, user_model = define_account_and_user('AssocNilTraitUser')
      FactoryBakery.define(user_model) do
        association :account
        trait :without_account do
          account { nil }
        end
      end

      expect(FactoryBakery.bake(user_model, :without_account).account).to be_nil
      expect(account_model.count).to eq(0)
    end

    it 'lets a trait assigning another object opt out of the declaration' do
      account_model, user_model = define_account_and_user('AssocOtherTraitUser')
      other = account_model.create!(name: 'other')
      FactoryBakery.define(user_model) do
        association :account
        trait :with_other do
          account { other }
        end
      end

      expect(FactoryBakery.bake(user_model, :with_other).account).to equal(other)
    end

    it 'raises clearly when the target is not ActiveRecord' do
      poro = define_class('AssocPoroUser') { attr_accessor :account }
      FactoryBakery.define(poro) { association :account }

      expect { FactoryBakery.bake(poro) }
        .to raise_error(FactoryBakery::Error, /no associations on .*AssocPoroUser.*it is not ActiveRecord/)
    end
  end

  describe 'automatic building' do
    it 'builds nothing undeclared in :none mode, even for a required belongs_to' do
      account_model, user_model = define_account_and_user('AssocNoneUser')
      FactoryBakery::Associations.mode = :none

      user = FactoryBakery.bake(user_model)

      expect(user.account).to be_nil
      expect(user.account_id).to be_nil
      expect(user).not_to be_valid
      expect(account_model.count).to eq(0)
    end

    it 'still builds nothing in the accepted-but-not-yet-implemented modes' do
      account_model, user_model = define_account_and_user('AssocFutureModeUser')

      %i[required_only all].each do |mode|
        FactoryBakery::Associations.mode = mode

        expect(FactoryBakery.bake(user_model).account).to be_nil
        expect(account_model.count).to eq(0)
      end
    end
  end
end
