# frozen_string_literal: true

require 'spec_helper'
require 'active_support/notifications'
require 'factory_bakery/associations'

# Public-API behavior of A11: the :required_only mode auto-builds every
# required belongs_to through the heuristics layer, with cycle detection by
# reflection path. Assertions only touch define/bake/bake!, row counts, SQL
# INSERT counts, and the plugin's public configuration.
RSpec.describe 'FactoryBakery associations :required_only mode' do
  before do
    FactoryBakery.reset_plugins!
    FactoryBakery.register_plugin(FactoryBakery::Associations::Plugin)
    FactoryBakery::Associations.mode = :required_only
  end

  after do
    FactoryBakery.reset_plugins!
    FactoryBakery::Associations.reset_configuration!
  end

  # Counts SQL INSERTs through a public notification.
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

  # User -> Account -> Company, all required via `optional: false`.
  def define_company_account_user(prefix)
    company = define_model("#{prefix}Company", name: :string)
    account = define_model("#{prefix}Account", name: :string, company_id: :integer) do
      belongs_to :company, class_name: "#{prefix}Company", optional: false
    end
    user = define_model("#{prefix}User", name: :string, account_id: :integer) do
      belongs_to :account, class_name: "#{prefix}Account", optional: false
    end
    [company, account, user]
  end

  describe 'automatic building of required belongs_to' do
    it 'builds the whole required chain unsaved with zero INSERTs under bake' do
      company_model, account_model, user_model = define_company_account_user('ReqChain')

      user = nil
      inserts = inserts_in { user = FactoryBakery.bake(user_model) }

      expect(inserts).to eq(0)
      expect([user.account.class, user.account.company.class]).to eq([account_model, company_model])
      expect([user.new_record?, user.account.new_record?, user.account.company.new_record?])
        .to eq([true, true, true])
      expect([user_model.count, account_model.count, company_model.count]).to eq([0, 0, 0])
    end

    it 'persists the whole chain atomically under bake!' do
      company_model, account_model, user_model = define_company_account_user('ReqBang')

      user = FactoryBakery.bake!(user_model)

      expect([user.persisted?, user.account.persisted?, user.account.company.persisted?])
        .to eq([true, true, true])
      expect([user.account_id, user.account.company_id])
        .to eq([user.account.id, user.account.company.id])
      expect([user_model.count, account_model.count, company_model.count]).to eq([1, 1, 1])
    end

    it 'applies the parent class registered factory' do
      _company_model, account_model, user_model = define_company_account_user('ReqFactory')
      FactoryBakery.define(account_model) { name { 'Acme' } }

      expect(FactoryBakery.bake(user_model).account.name).to eq('Acme')
    end

    it 'leaves an optional belongs_to with a nullable FK nil' do
      user_model = define_model('ReqOptionalUser', name: :string, account_id: :integer) do
        belongs_to :account, class_name: 'ReqOptionalAccount', optional: true
      end
      define_model('ReqOptionalAccount', name: :string)

      user = FactoryBakery.bake(user_model)

      expect(user.account).to be_nil
      expect(user.account_id).to be_nil
    end

    it 'treats a NOT NULL FK as required even when the association is optional' do
      define_model('ReqNotNullTeam', name: :string)
      player_model = define_model('ReqNotNullPlayer', name: :string, team_id: { type: :integer, null: false }) do
        belongs_to :team, class_name: 'ReqNotNullTeam', optional: true
      end

      player = FactoryBakery.bake(player_model)

      expect(player.team).to be_a(Object.const_get('ReqNotNullTeam'))
      expect(player.team).to be_new_record
    end

    it 'treats a create-only presence validator as required' do
      account_model = define_model('ReqOnCreateAccount', name: :string)
      user_model = define_model('ReqOnCreateUser', account_id: :integer) do
        belongs_to :account, class_name: 'ReqOnCreateAccount', optional: true
        validates :account, presence: true, on: :create
      end

      expect(FactoryBakery.bake(user_model).account).to be_a(account_model)
    end

    it 'treats a conditional presence validator as required' do
      account_model = define_model('ReqConditionalAccount', name: :string)
      user_model = define_model('ReqConditionalUser', account_id: :integer) do
        belongs_to :account, class_name: 'ReqConditionalAccount', optional: true
        validates :account, presence: true, if: -> { true }
      end

      expect(FactoryBakery.bake(user_model).account).to be_a(account_model)
    end

    it 'builds every required belongs_to on a class without leaking the reflection path between siblings' do
      person_model = define_model('ReqSiblingsPerson', name: :string)
      order_model = define_model('ReqSiblingsOrder', buyer_id: :integer, seller_id: :integer) do
        belongs_to :buyer, class_name: 'ReqSiblingsPerson', optional: false
        belongs_to :seller, class_name: 'ReqSiblingsPerson', optional: false
      end

      order = FactoryBakery.bake(order_model)

      expect([order.buyer.class, order.seller.class]).to eq([person_model, person_model])
      expect(order.buyer).not_to equal(order.seller)
    end

    it 'rolls back the whole auto-built chain when the root save fails' do
      company_model, account_model, user_model = define_company_account_user('ReqRollback')
      user_model.validates :name, absence: true

      expect { FactoryBakery.bake!(user_model, name: 'invalid') }
        .to raise_error(ActiveRecord::RecordInvalid)

      expect([user_model.count, account_model.count, company_model.count]).to eq([0, 0, 0])
    end
  end

  describe 'cycle detection by reflection path' do
    def define_mutual_required(prefix, inverse_of: false)
      account = define_model("#{prefix}Account", owner_id: :integer)
      user = define_model("#{prefix}User", account_id: :integer)

      if inverse_of
        account.belongs_to :owner, class_name: "#{prefix}User", optional: false, inverse_of: :account
      else
        account.belongs_to :owner, class_name: "#{prefix}User", optional: false
      end
      user.belongs_to :account, class_name: "#{prefix}Account", optional: false
      [account, user]
    end

    it 'raises CyclicAssociationError naming the reflection path for mutual required FKs' do
      _account_model, user_model = define_mutual_required('ReqCycle')

      expect { FactoryBakery.bake(user_model) }.to raise_error(FactoryBakery::CyclicAssociationError) { |error|
        expect(error).to be_a(FactoryBakery::Error)
        expect(error.message).to include('ReqCycleUser#account -> ReqCycleAccount#owner -> ReqCycleUser#account')
        expect(error.message).to match(/owner \{ nil \}/)
        expect(error.message).to match(/optional/)
      }
    end

    it 'still raises when inverse_of is set, because an insert cycle cannot be persisted' do
      _account_model, user_model = define_mutual_required('ReqCycleInverse', inverse_of: true)

      expect { FactoryBakery.bake(user_model) }.to raise_error(
        FactoryBakery::CyclicAssociationError,
        /ReqCycleInverseUser#account -> ReqCycleInverseAccount#owner/
      )
    end

    it 'raises for a required self-reference' do
      node = define_model('ReqSelfNode', parent_id: :integer) do
        belongs_to :parent, class_name: 'ReqSelfNode', optional: false
      end

      expect { FactoryBakery.bake(node) }
        .to raise_error(FactoryBakery::CyclicAssociationError, /ReqSelfNode#parent -> ReqSelfNode#parent/)
    end

    it 'allows a finite same-class chain ended by a factory' do
      node = define_model('ReqFiniteNode', name: :string, parent_id: :integer) do
        belongs_to :parent, class_name: 'ReqFiniteNode', optional: false
      end
      FactoryBakery.define(:req_finite_root, klass: node) { parent { nil } }
      FactoryBakery.define(node) { association :parent, factory: :req_finite_root }

      baked = FactoryBakery.bake(node)

      expect([baked.parent.class, baked.parent.parent]).to eq([node, nil])
    end

    it 'leaves no stale reflection path after an error, so the next bake can be overridden' do
      _account_model, user_model = define_mutual_required('ReqCycleRecover')

      expect { FactoryBakery.bake(user_model) }.to raise_error(FactoryBakery::CyclicAssociationError)

      recovered = FactoryBakery.bake(user_model, account: nil)
      expect(recovered.account).to be_nil
    end

    it 'is bounded by the max bake depth backstop for a long acyclic required chain' do
      define_model('ReqDeepC', name: :string)
      define_model('ReqDeepB', c_id: :integer) do
        belongs_to :c, class_name: 'ReqDeepC', optional: false
      end
      a_model = define_model('ReqDeepA', b_id: :integer) do
        belongs_to :b, class_name: 'ReqDeepB', optional: false
      end

      previous = FactoryBakery.max_bake_depth
      FactoryBakery.max_bake_depth = 2
      expect { FactoryBakery.bake(a_model) }
        .to raise_error(FactoryBakery::NestingTooDeepError, /max_bake_depth \(2\)/)
    ensure
      FactoryBakery.max_bake_depth = previous
    end
  end

  describe 'precedence over auto-building' do
    it 'lets an explicit association declaration win without building a stray parent' do
      account_model = define_model('ReqDeclWinsAccount', name: :string)
      user_model = define_model('ReqDeclWinsUser', account_id: :integer) do
        belongs_to :account, class_name: 'ReqDeclWinsAccount', optional: false
      end
      FactoryBakery.define(user_model) { association :account, name: 'declared' }

      user = nil
      inserts = inserts_in { user = FactoryBakery.bake!(user_model) }

      expect(user.account.name).to eq('declared')
      expect([user_model.count, account_model.count]).to eq([1, 1])
      expect(inserts).to eq(2)
    end

    it 'lets a call-site association object suppress auto-build' do
      company_model, account_model, user_model = define_company_account_user('ReqObjOverride')
      company = company_model.create!(name: 'existing company')
      existing = account_model.create!(name: 'existing', company: company)

      user = FactoryBakery.bake!(user_model, account: existing)

      expect(user.account).to equal(existing)
      expect(account_model.count).to eq(1)
    end

    it 'lets a call-site FK override suppress auto-build' do
      company_model, account_model, user_model = define_company_account_user('ReqFkOverride')
      company = company_model.create!(name: 'existing company')
      existing = account_model.create!(name: 'existing', company: company)

      user = FactoryBakery.bake(user_model, account_id: existing.id)

      expect(user.account_id).to eq(existing.id)
      expect(account_model.count).to eq(1)
    end

    it 'lets a trait assigning nil opt out of auto-build' do
      _company_model, _account_model, user_model = define_company_account_user('ReqTraitNil')
      FactoryBakery.define(user_model) do
        trait :without_account do
          account { nil }
        end
      end

      expect(FactoryBakery.bake(user_model, :without_account).account).to be_nil
    end

    it 'lets initialize_with suppress auto-build' do
      company_model, account_model, user_model = define_company_account_user('ReqInitWith')
      company = company_model.create!(name: 'existing company')
      existing = account_model.create!(name: 'existing', company: company)
      FactoryBakery.define(user_model) { initialize_with(account_id: existing.id) }

      expect(FactoryBakery.bake(user_model).account_id).to eq(existing.id)
      expect(account_model.count).to eq(1)
    end
  end

  describe 'required polymorphic associations' do
    def define_required_comment(prefix)
      define_model("#{prefix}Post", title: :string)
      define_model("#{prefix}Comment", commentable_type: :string, commentable_id: :integer) do
        belongs_to :commentable, polymorphic: true, optional: false
      end
    end

    it 'raises an actionable error when there is no declaration or override' do
      comment_model = define_required_comment('ReqPoly')

      expect { FactoryBakery.bake(comment_model) }.to raise_error(FactoryBakery::Error) { |error|
        expect(error.message).to match(/required polymorphic.*commentable/)
        expect(error.message).to match(/association :commentable, factory:/)
        expect(error.message).to match(/commentable:/)
      }
    end

    it 'passes when an association declaration names the target' do
      comment_model = define_required_comment('ReqPolyDeclared')
      post_model = Object.const_get('ReqPolyDeclaredPost')
      FactoryBakery.define(comment_model) { association :commentable, factory: post_model }

      comment = FactoryBakery.bake!(comment_model)

      expect(comment.commentable).to be_a(post_model)
      expect(comment.commentable_type).to eq(post_model.polymorphic_name)
    end
  end

  describe 'mode and PORO boundaries' do
    it 'does nothing in :none mode even for a required belongs_to' do
      _company_model, account_model, user_model = define_company_account_user('ReqNone')

      FactoryBakery::Associations.mode = :none
      user = FactoryBakery.bake(user_model)

      expect(user.account).to be_nil
      expect(user).not_to be_valid
      expect(account_model.count).to eq(0)
    end

    it 'still builds required belongs_to when :all mode is selected' do
      _company_model, account_model, user_model = define_company_account_user('ReqAll')

      FactoryBakery::Associations.mode = :all
      user = FactoryBakery.bake(user_model)

      expect(user.account).to be_a(account_model)
      expect(account_model.count).to eq(0)
    end

    it 'leaves POROs with no reflections unaffected' do
      poro = define_class('ReqOnlyPoro') { attr_accessor :name }

      record = FactoryBakery.bake(poro)

      expect(record).to be_a(poro)
      expect(record).not_to respond_to(:reflect_on_all_associations)
    end
  end
end
