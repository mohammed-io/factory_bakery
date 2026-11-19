# frozen_string_literal: true

require 'spec_helper'

# Issue #50: a validator's if:/unless: conditions only shape generation when
# they hold for the record being baked. The conditions are resolved against the
# in-progress record (after overrides/declarations are assigned) and must never
# crash a bake or leak between bakes of the same class with different state.
RSpec.describe 'condition-aware validators (issue #50)' do
  include DefineConstantMacros

  describe 'presence and absence guarded by complementary conditions' do
    let!(:model) do
      define_model('ConditionalUri', uri: :string, remote: :boolean) do
        validates :uri, presence: true, if: :remote?
        validates :uri, absence: true, unless: :remote?

        def remote?
          !!remote
        end
      end
    end

    it 'leaves the attribute nil when the presence condition is false' do
      record = FactoryBakery.bake(model, remote: false)

      expect(record.uri).to be_nil
      expect(record).to be_valid
    end

    it 'generates a present value when the presence condition is true' do
      record = FactoryBakery.bake(model, remote: true)

      expect(record.uri).not_to be_nil
      expect(record.uri).not_to be_empty
      expect(record).to be_valid
    end
  end

  describe 'mutually exclusive format validators' do
    let!(:model) do
      define_model('ConditionalCode', code: :string, local: :boolean) do
        validates :code, format: { with: /\A[a-z]+\z/ }, if: :local?
        validates :code, format: { with: /\A[A-Z]+\z/ }, unless: :local?

        def local?
          !!local
        end
      end
    end

    it 'generates a value satisfying only the applicable format' do
      local = FactoryBakery.bake(model, local: true)
      remote = FactoryBakery.bake(model, local: false)

      expect(local.code).to match(/\A[a-z]+\z/)
      expect(remote.code).to match(/\A[A-Z]+\z/)
      expect(local).to be_valid
      expect(remote).to be_valid
    end
  end

  describe 'dirty-tracking conditions' do
    let!(:model) do
      define_model('DirtyConditionUsername', username: { type: :string, default: '' }) do
        validates :username, presence: true, if: -> { will_save_change_to_username? }
      end
    end

    it 'sees the generated attribute as changing while its conditions run' do
      record = FactoryBakery.bake(model)

      expect(record.username).not_to eq('')
      expect(record).to be_valid
    end
  end

  describe 'a condition that raises' do
    let!(:model) do
      define_model('RaisingConditionCode', code: :string) do
        validates :code, length: { is: 5 }, if: -> { raise 'condition exploded' }
      end
    end

    it 'treats the validator as applicable without crashing the bake' do
      record = FactoryBakery.bake(model)

      expect(record.code.length).to eq(5)
    end
  end

  describe 'per-bake resolution with different parent state' do
    let!(:account_model) do
      define_model('ConditionalAccount', remote: :boolean)
    end

    let!(:keypair_model) do
      define_model('ConditionalKeypair', uri: :string, account_id: :integer) do
        belongs_to :account, class_name: 'ConditionalAccount'

        validates :uri, presence: true, if: :remote?
        validates :uri, absence: true, unless: :remote?

        def remote?
          account&.remote?
        end
      end
    end

    it 'does not reuse constraints cached from a bake with other parent state' do
      local = FactoryBakery.bake(keypair_model, account: FactoryBakery.bake(account_model, remote: false))
      remote = FactoryBakery.bake(keypair_model, account: FactoryBakery.bake(account_model, remote: true))

      expect(local.uri).to be_nil
      expect(remote.uri).not_to be_nil
      expect(local).to be_valid
      expect(remote).to be_valid
    end
  end

  describe 'supported condition forms' do
    let!(:model) do
      define_model('ConditionFormCode', code: :string, flag: :boolean) do
        validates :code, length: { is: 4 }, if: [:flag?, ->(record) { record.flag == true }]

        def flag?
          flag
        end
      end
    end

    it 'accepts arrays of method names and arity-one procs' do
      record = FactoryBakery.bake(model, flag: true)

      expect(record.code.length).to eq(4)
      expect(record).to be_valid
    end
  end
end
