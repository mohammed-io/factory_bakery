# frozen_string_literal: true

require 'spec_helper'

# Issue #57: a schema-backed model can be validated through attributes that are
# not columns (a password held only in memory, an acceptance flag, a
# confirmation twin). When the model exposes a setter, heuristics fill them
# like columns, and the required-only rule decides whether they are needed.
RSpec.describe 'validated virtual attributes on ActiveRecord models (issue #57)' do
  include DefineConstantMacros

  describe 'a password-style virtual attribute' do
    let!(:model) do
      define_model('CredentialUser', email: :string) do
        attr_accessor :password, :password_confirmation

        validates :email, presence: true
        validates :password, presence: true, confirmation: true
      end
    end

    it 'fills the password and matches its confirmation twin' do
      record = FactoryBakery.bake(model)

      expect(record.password).to be_present
      expect(record.password_confirmation).to eq(record.password)
      expect(record).to be_valid
    end

    it 'keeps a call-site password and its confirmation in sync' do
      record = FactoryBakery.bake(model, password: 'correct horse battery staple')

      expect(record.password).to eq('correct horse battery staple')
      expect(record.password_confirmation).to eq('correct horse battery staple')
      expect(record).to be_valid
    end

    it 'fills a password whose validators only confirm it and cap its length' do
      # The shape has_secure_password declares: confirmation plus a maximum
      # length, neither of which rejects nil.
      model = define_model('DigestlessUser', email: :string) do
        attr_accessor :password, :password_confirmation

        validates :password, confirmation: { allow_blank: true }
        validates :password, length: { maximum: 72 }, allow_nil: true
      end

      record = FactoryBakery.bake(model)

      expect(record.password).to be_present
      expect(record.password.length).to be <= 72
      expect(record.password_confirmation).to eq(record.password)
      expect(record).to be_valid
    end

    it 'persists through bake! (the password is not a column)' do
      record = FactoryBakery.bake!(model)

      expect(record).to be_persisted
      expect(record.password).to be_present
      expect(record.password_confirmation).to eq(record.password)
    end
  end

  describe 'an acceptance-style virtual attribute' do
    it 'fills the accepted value when nil is rejected' do
      model = define_model('AgreementUser', email: :string) do
        attr_accessor :terms_of_service

        validates :terms_of_service, acceptance: { allow_nil: false }
      end

      record = FactoryBakery.bake(model)

      expect(record.terms_of_service).to be_truthy
      expect(record).to be_valid
    end

    it 'fills the default accepted value for a plain acceptance validator' do
      model = define_model('DefaultAgreementUser', email: :string) do
        attr_accessor :terms_of_service

        validates :terms_of_service, acceptance: true
      end

      record = FactoryBakery.bake(model)

      expect(record.terms_of_service).to eq('1')
      expect(record).to be_valid
    end
  end

  describe 'the required-only rule' do
    it 'fills a virtual attribute whose validator rejects nil' do
      model = define_model('NicknameUser', email: :string) do
        attr_accessor :nickname

        validates :nickname, length: { minimum: 2 }
      end

      record = FactoryBakery.bake(model)

      expect(record.nickname.length).to be >= 2
      expect(record).to be_valid
    end

    it 'leaves a virtual attribute alone when its validators allow nil' do
      model = define_model('OptionalNicknameUser', email: :string) do
        attr_accessor :nickname

        validates :nickname, length: { maximum: 8 }
      end

      record = FactoryBakery.bake(model)

      expect(record.nickname).to be_nil
      expect(record).to be_valid
    end

    it 'resolves an if: condition for the record being baked' do
      model = define_model('ConditionalNicknameUser', email: :string, needs_nickname: :boolean) do
        attr_accessor :nickname

        validates :nickname, presence: true, if: :needs_nickname?

        def needs_nickname?
          !!needs_nickname
        end
      end

      skipped = FactoryBakery.bake(model, needs_nickname: false)
      required = FactoryBakery.bake(model, needs_nickname: true)

      expect(skipped.nickname).to be_nil
      expect(skipped).to be_valid
      expect(required.nickname).to be_present
      expect(required).to be_valid
    end
  end

  describe 'the attribute universe' do
    it 'adds a validated virtual attribute that has a public setter' do
      model = define_model('SetterNicknameUser', email: :string) do
        attr_accessor :nickname

        validates :nickname, presence: true
      end

      expect(FactoryBakery::MapperRegistry.attribute_universe(model)).to include('nickname')
      expect(FactoryBakery.bake(model).nickname).to be_present
    end

    it 'never adds an association name' do
      define_model('UniverseAccount', name: :string)
      model = define_model('UniverseMember', account_id: :integer) do
        belongs_to :account, class_name: 'UniverseAccount', optional: true

        validates :account, presence: true
      end

      universe = FactoryBakery::MapperRegistry.attribute_universe(model)
      record = FactoryBakery.bake(model)

      expect(universe).not_to include('account')
      expect(record.account).to be_nil
      expect(record.account_id).to be_nil
    end

    it 'never adds a foreign-key or polymorphic type column more than once' do
      model = define_model('UniverseOwner', owner_id: :integer, owner_type: :string) do
        belongs_to :owner, polymorphic: true, optional: true

        validates :owner, presence: true
      end

      universe = FactoryBakery::MapperRegistry.attribute_universe(model)
      record = FactoryBakery.bake(model)

      expect(universe).not_to include('owner')
      expect(universe.count('owner_id')).to eq(1)
      expect(universe.count('owner_type')).to eq(1)
      expect(record.owner_id).to be_nil
      expect(record.owner_type).to be_nil
    end

    it 'ignores a validated virtual attribute without a setter' do
      model = define_model('ReadOnlyTokenUser', email: :string) do
        attr_reader :token

        validates :token, presence: true
      end

      expect(FactoryBakery::MapperRegistry.attribute_universe(model)).not_to include('token')
      expect { FactoryBakery.bake(model) }.not_to raise_error
    end
  end
end
