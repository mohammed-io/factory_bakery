# frozen_string_literal: true

require 'spec_helper'
require 'factory_bakery/associations'

# Issue #53: in :required_only, a direct has_one with a presence validator that
# applies to the populated owner is built automatically. Conditions are read
# for the owner being baked, and the child is built through the association so
# its scope and inverse apply without triggering a second owner build.
RSpec.describe 'FactoryBakery associations required has_one (issue #53)' do
  include DefineConstantMacros

  before do
    FactoryBakery.reset_plugins!
    FactoryBakery.register_plugin(FactoryBakery::Associations::Plugin)
    FactoryBakery::Associations.reset_configuration!
    FactoryBakery::Associations.mode = :required_only
  end

  after do
    FactoryBakery.reset_plugins!
    FactoryBakery::Associations.reset_configuration!
  end

  # Owner has_one Profile; Profile's required belongs_to would otherwise grow a
  # second Owner and raise CyclicAssociationError.
  def define_required_pair(prefix)
    profile = define_model("#{prefix}Profile", owner_id: :integer, nickname: :string) do
      belongs_to :owner, class_name: "#{prefix}Owner", optional: false, inverse_of: :profile
    end
    owner = define_model("#{prefix}Owner", name: :string) do
      has_one :profile, class_name: "#{prefix}Profile", foreign_key: :owner_id, inverse_of: :owner
      validates :profile, presence: true
    end
    [owner, profile]
  end

  describe 'automatic building' do
    it 'builds a scoped child that points back to the same owner and validates' do
      profile_model = define_model('ReqHoScopedEmail', user_id: :integer, primary: :boolean) do
        belongs_to :user, class_name: 'ReqHoScopedUser', optional: false
      end
      owner_model = define_model('ReqHoScopedUser', name: :string) do
        has_one :primary_email, -> { where(primary: true) },
                class_name: 'ReqHoScopedEmail', foreign_key: :user_id
        validates :primary_email, presence: true
      end

      owner = FactoryBakery.bake(owner_model)

      expect(owner.primary_email).to be_a(profile_model)
      expect(owner.primary_email.primary).to be(true)
      expect(owner.primary_email.user).to equal(owner)
      expect(owner).to be_valid
    end

    it 'builds the child without a cycle when it requires belongs_to :owner' do
      owner_model, profile_model = define_required_pair('ReqHoCycle')

      owner = FactoryBakery.bake(owner_model)

      expect(owner.profile).to be_a(profile_model)
      expect(owner.profile.owner).to equal(owner)
      expect(owner).to be_valid
    end

    it 'does not build a has_one without a presence validator' do
      define_model('ReqHoOptionalProfile', owner_id: :integer)
      owner_model = define_model('ReqHoOptionalOwner', name: :string) do
        has_one :profile, class_name: 'ReqHoOptionalProfile', foreign_key: :owner_id
      end

      expect(FactoryBakery.bake(owner_model).profile).to be_nil
    end

    it 'does not build when the presence validator condition does not apply' do
      profile_model = define_model('ReqHoSkipProfile', owner_id: :integer)
      owner_model = define_model('ReqHoSkipOwner', name: :string) do
        attr_accessor :skip_profile

        has_one :profile, class_name: 'ReqHoSkipProfile', foreign_key: :owner_id
        validates :profile, presence: true, unless: :skip_profile
      end

      expect(FactoryBakery.bake(owner_model).profile).to be_a(profile_model)

      skipped = FactoryBakery.bake(owner_model, skip_profile: true)
      expect(skipped.profile).to be_nil
      expect(skipped).to be_valid
    end

    it 'does nothing in :none mode' do
      owner_model, = define_required_pair('ReqHoNone')
      FactoryBakery::Associations.mode = :none

      expect(FactoryBakery.bake(owner_model).profile).to be_nil
    end

    it 'honours inverse_of: false without growing a second owner' do
      define_model('ReqHoNoInverseProfile', owner_id: :integer)
      owner_model = define_model('ReqHoNoInverseOwner', name: :string) do
        has_one :profile, class_name: 'ReqHoNoInverseProfile', foreign_key: :owner_id, inverse_of: false
        validates :profile, presence: true
      end

      expect(FactoryBakery.bake(owner_model).profile).to be_a(Object.const_get('ReqHoNoInverseProfile'))
    end
  end

  describe 'precedence over auto-building' do
    it 'lets a call-site assignment win without building a stray child' do
      owner_model, profile_model = define_required_pair('ReqHoOverride')
      existing = profile_model.new(nickname: 'existing')

      owner = FactoryBakery.bake!(owner_model, profile: existing)

      expect(owner.profile).to equal(existing)
      expect(profile_model.count).to eq(1)
    end

    it 'lets an explicit association declaration win' do
      owner_model, = define_required_pair('ReqHoDeclared')
      FactoryBakery.define(owner_model) { association :profile, with: { nickname: 'declared' } }

      owner = FactoryBakery.bake(owner_model)

      expect(owner.profile.nickname).to eq('declared')
    end

    it 'lets skip suppress auto-build' do
      owner_model, = define_required_pair('ReqHoSkipped')
      FactoryBakery.define(owner_model) { skip :profile }

      expect(FactoryBakery.bake(owner_model).profile).to be_nil
    end
  end

  describe 'in :all past max_depth' do
    # :all builds every child within max_depth. A deeper owner gets no
    # optional children, but its required has_one must still be built, or the
    # owner is invalid and Rails' belongs_to autosave silently skips it.
    it 'still builds the required has_one of a nested owner' do
      owner_model, profile_model = define_required_pair('ReqHoDeep')
      holder_model = define_model('ReqHoDeepHolder', owner_id: :integer) do
        belongs_to :owner, class_name: 'ReqHoDeepOwner', optional: false
      end
      FactoryBakery::Associations.mode = :all
      FactoryBakery::Associations.max_depth = 1

      holder = FactoryBakery.bake!(holder_model)

      expect(holder.owner.profile).to be_a(profile_model)
      expect([holder.owner, holder.owner.profile]).to all(be_persisted)
      expect(owner_model.count).to eq(1)
    end
  end

  describe 'persistence' do
    it 'persists the owner and child together under bake!' do
      owner_model, profile_model = define_required_pair('ReqHoBang')

      owner = FactoryBakery.bake!(owner_model)

      expect([owner.persisted?, owner.profile.persisted?]).to eq([true, true])
      expect([owner_model.count, profile_model.count]).to eq([1, 1])
      expect(owner.profile.owner_id).to eq(owner.id)
    end

    it 'rolls back both records when the child fails validation' do
      owner_model, profile_model = define_required_pair('ReqHoRollback')
      profile_model.validates :nickname, inclusion: { in: ['ok'] }
      FactoryBakery.define(profile_model) { nickname { 'bad' } }

      expect { FactoryBakery.bake!(owner_model) }
        .to raise_error(FactoryBakery::IncompletePersistenceError, /Profile/)

      expect([owner_model.count, profile_model.count]).to eq([0, 0])
    end
  end
end
