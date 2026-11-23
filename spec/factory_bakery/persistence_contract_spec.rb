# frozen_string_literal: true

require 'spec_helper'
require 'active_support/notifications'

RSpec.describe 'FactoryBakery bake! persistence contract' do
  include DefineConstantMacros

  # Counts SQL INSERTs emitted by the block. It is a public, observable signal
  # that `bake` stays database-free and that `bake!` writes what it should.
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

  describe 'atomicity', :savepoints do
    it 'leaves no rows from a nested bake! when the root save! fails' do
      account_model = define_model('ContractAccount', name: :string)
      user_model = define_model('ContractUser', name: :string, account_id: :integer) do
        belongs_to :account, class_name: 'ContractAccount', optional: true
        validates :name, absence: true
      end

      FactoryBakery.define(user_model) do
        account { FactoryBakery.bake!(account_model) }
      end

      expect { FactoryBakery.bake!(user_model, name: 'invalid') }
        .to raise_error(ActiveRecord::RecordInvalid)

      expect(user_model.count).to eq(0)
      expect(account_model.count).to eq(0)
    end

    it 'leaves no rows from a nested bake when the root save! fails' do
      account_model = define_model('ContractBakeAccount', name: :string)
      user_model = define_model('ContractBakeUser', name: :string, account_id: :integer) do
        belongs_to :account, class_name: 'ContractBakeAccount', optional: true
        validates :name, absence: true
      end

      FactoryBakery.define(user_model) do
        account { FactoryBakery.bake(account_model) }
      end

      expect { FactoryBakery.bake!(user_model, name: 'invalid') }
        .to raise_error(ActiveRecord::RecordInvalid)

      expect(user_model.count).to eq(0)
      expect(account_model.count).to eq(0)
    end

    it 'rolls back to a savepoint when the caller rescues inside an outer transaction' do
      account_model = define_model('SavepointAccount', name: :string)
      user_model = define_model('SavepointUser', name: :string, account_id: :integer) do
        belongs_to :account, class_name: 'SavepointAccount', optional: true
        validates :name, absence: true
      end

      FactoryBakery.define(user_model) do
        account { FactoryBakery.bake!(account_model) }
      end

      ActiveRecord::Base.transaction do
        expect { FactoryBakery.bake!(user_model, name: 'invalid') }
          .to raise_error(ActiveRecord::RecordInvalid)

        expect(user_model.count).to eq(0)
        expect(account_model.count).to eq(0)

        # The outer transaction is still usable after the savepoint rollback.
        account_model.create!(name: 'outer')
      end

      expect(account_model.pluck(:name)).to eq(['outer'])
    end
  end

  describe 'verify and raise', :savepoints do
    it 'raises IncompletePersistenceError when autosave: false leaves a generated parent unsaved' do
      account_model = define_model('NoAutosaveAccount', name: :string)
      user_model = define_model('NoAutosaveUser', name: :string, account_id: :integer) do
        belongs_to :account, class_name: 'NoAutosaveAccount', optional: true, autosave: false
      end

      FactoryBakery.define(user_model) do
        account { FactoryBakery.bake(account_model) }
      end

      expect { FactoryBakery.bake!(user_model) }
        .to raise_error(FactoryBakery::IncompletePersistenceError, /NoAutosaveAccount.*account/) { |error|
          expect(error).to be_a(FactoryBakery::Error)
          expect(error.message).to match(/persist.*explicitly|autosave|validate/i)
        }

      expect(user_model.count).to eq(0)
      expect(account_model.count).to eq(0)
    end

    it 'raises IncompletePersistenceError when validate: false leaves an invalid generated parent unsaved' do
      account_model = define_model('UnvalidatedAccount', name: :string) do
        validates :name, absence: true
      end
      user_model = define_model('UnvalidatedUser', name: :string, account_id: :integer) do
        belongs_to :account, class_name: 'UnvalidatedAccount', optional: true, validate: false
      end

      FactoryBakery.define(user_model) do
        account { FactoryBakery.bake(account_model, name: 'invalid') }
      end

      expect { FactoryBakery.bake!(user_model) }
        .to raise_error(FactoryBakery::IncompletePersistenceError, /UnvalidatedAccount.*account/)

      expect(user_model.count).to eq(0)
      expect(account_model.count).to eq(0)
    end

    it 'names a generated collection member and its association when it stays unsaved' do
      post_model = define_model('CollectionPost', title: :string)
      comment_model = define_model('CollectionComment', body: :string, post_id: :integer) do
        belongs_to :post, class_name: 'CollectionPost', optional: true
      end
      post_model.has_many :comments,
                          class_name: 'CollectionComment',
                          foreign_key: :post_id,
                          inverse_of: :post,
                          autosave: false

      FactoryBakery.define(post_model) do
        comments { [FactoryBakery.bake(comment_model)] }
      end

      expect { FactoryBakery.bake!(post_model) }
        .to raise_error(FactoryBakery::IncompletePersistenceError, /CollectionComment.*comments/)

      expect(post_model.count).to eq(0)
      expect(comment_model.count).to eq(0)
    end
  end

  describe 'happy paths' do
    it 'persists nested bake parents through autosave and returns the root' do
      account_model = define_model('AutosaveAccount', name: :string)
      user_model = define_model('AutosaveUser', name: :string, account_id: :integer) do
        belongs_to :account, class_name: 'AutosaveAccount', optional: true
      end

      FactoryBakery.define(user_model) do
        account { FactoryBakery.bake(account_model) }
      end

      user = FactoryBakery.bake!(user_model)

      expect(user).to be_a(user_model)
      expect(user).to be_persisted
      expect(user.account).to be_persisted
      expect(user_model.count).to eq(1)
      expect(account_model.count).to eq(1)
    end

    it 'persists a nested bake! graph and returns the root' do
      account_model = define_model('NestedBakeAccount', name: :string)
      user_model = define_model('NestedBakeUser', name: :string, account_id: :integer) do
        belongs_to :account, class_name: 'NestedBakeAccount', optional: true
      end

      FactoryBakery.define(user_model) do
        account { FactoryBakery.bake!(account_model) }
      end

      user = FactoryBakery.bake!(user_model)

      expect(user).to be_persisted
      expect(user.account).to be_persisted
      expect(user_model.count).to eq(1)
      expect(account_model.count).to eq(1)
    end
  end

  describe 'non-persisting paths' do
    it 'keeps PORO bake! behaviour unchanged: no save! and no transaction' do
      poro = define_class('ContractPoro') { attr_accessor :name }

      record = FactoryBakery.bake!(poro, name: 'plain')

      expect(record).to be_a(poro)
      expect(record.name).to eq('plain')
      expect(record).not_to respond_to(:save!)
    end

    it 'never writes to the database during a plain bake' do
      model = define_model('NoWriteRecord', name: :string)

      inserts = inserts_in { FactoryBakery.bake(model) }

      expect(inserts).to eq(0)
      expect(model.count).to eq(0)
    end
  end
end
