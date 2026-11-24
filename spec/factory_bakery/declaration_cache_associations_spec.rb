# frozen_string_literal: true

require 'spec_helper'
require 'factory_bakery/associations'

# Association declarations are recorded with the definition that declares them
# (ADR-0009) and replayed to every bake. Observable contract: the definition
# block runs once, each bake still builds its own fresh parent, overrides and
# traits behave as before, and changing the plugin set starts the cache over.
RSpec.describe 'declaration cache with association declarations' do
  before do
    FactoryBakery.reset_plugins!
    FactoryBakery.register_plugin(FactoryBakery::Associations::Plugin)
    FactoryBakery::Associations.reset_configuration!
  end

  after do
    FactoryBakery.reset_plugins!
    FactoryBakery::Associations.reset_configuration!
  end

  let!(:account) { define_model('DeclCacheAccount', name: :string) }
  let!(:user) do
    define_model('DeclCacheUser', name: :string, account_id: :integer, other_id: :integer) do
      belongs_to :account, class_name: 'DeclCacheAccount', optional: false
    end
  end

  it 'runs the definition block once and still builds a fresh parent per bake' do
    runs = 0
    FactoryBakery.define(user) do
      runs += 1
      association :account, with: { name: 'declared parent' }
    end

    users = Array.new(3) { FactoryBakery.bake(user) }

    expect(runs).to eq(1)
    expect(users.map { _1.account.name }).to all(eq('declared parent'))
    expect(users.map(&:account).uniq(&:object_id).size).to eq(3)
  end

  it 'lets a call-site assignment beat the replayed declaration' do
    FactoryBakery.define(user) { association :account }
    FactoryBakery.bake(user)
    mine = account.new(name: 'mine')

    expect(FactoryBakery.bake(user, account: mine).account).to equal(mine)
  end

  it 'replays a declaration made in a trait only when the trait is requested' do
    FactoryBakery.define(user) do
      trait(:with_account) { association :account, with: { name: 'from trait' } }
      other_id { 1 }
    end

    with = Array.new(2) { FactoryBakery.bake(user, :with_account) }
    without = FactoryBakery.bake(user)

    expect(with.map { _1.account.name }).to all(eq('from trait'))
    expect(without.account.name).not_to eq('from trait')
  end

  it 'lets a later trait replace an association declared by the base' do
    FactoryBakery.define(user) do
      association :account, with: { name: 'base' }
      trait(:named) { association :account, with: { name: 'trait' } }
    end

    2.times { FactoryBakery.bake(user) }

    expect(FactoryBakery.bake(user, :named).account.name).to eq('trait')
    expect(FactoryBakery.bake(user).account.name).to eq('base')
  end

  it 'starts over when the plugin is removed, so the declaration is refused again' do
    FactoryBakery.define(user) { association :account }
    FactoryBakery.bake(user)

    FactoryBakery.unregister_plugin(FactoryBakery::Associations::Plugin)

    expect { FactoryBakery.bake(user) }.to raise_error(FactoryBakery::Error, /requires the associations plugin/)
  end

  it 'still evaluates an association block on every bake' do
    calls = 0
    account_class = account
    FactoryBakery.define(user) do
      association(:account) do |_owner|
        calls += 1
        account_class.new(name: "block-#{calls}")
      end
    end

    names = Array.new(2) { FactoryBakery.bake(user).account.name }

    expect(names).to eq(%w[block-1 block-2])
  end

  describe 'reusable with: values' do
    # An entry is replayed to every later bake, so its with: values are
    # shared. The observable contract: a with: value that cannot change
    # under sharing records the layer once; anything else makes the layer be
    # evaluated on every bake, so each bake declares its own values. The
    # probe key has no setter on the account model, so any value bakes.
    def recorded_once?(value)
      runs = 0
      FactoryBakery.define(user) do
        runs += 1
        association :account, with: { probe: value }
      end

      Array.new(2) { FactoryBakery.bake(user) }
      runs == 1
    end

    it 'records the layer once when every with: value is safe to share' do
      aggregate_failures do
        expect(recorded_once?('declared parent')).to be(true)          # frozen String
        expect(recorded_once?(nil)).to be(true)
        expect(recorded_once?(true)).to be(true)
        expect(recorded_once?(false)).to be(true)
        expect(recorded_once?(1)).to be(true)                          # Integer
        expect(recorded_once?(0.5)).to be(true)                        # Float
        expect(recorded_once?(:declared)).to be(true)                  # Symbol
        expect(recorded_once?(1..2)).to be(true)                       # Range of those
        expect(recorded_once?([1, 'a', :b].freeze)).to be(true)        # frozen Array of those
        expect(recorded_once?({ key: 'a' }.freeze)).to be(true)        # frozen Hash of those
        expect(recorded_once?(account)).to be(true)                    # Class
      end
    end

    it 'evaluates the layer on every bake when a with: value must not be shared' do
      aggregate_failures do
        expect(recorded_once?(String.new('a'))).to be(false)           # unfrozen String
        expect(recorded_once?(['a'])).to be(false)                     # unfrozen Array
        expect(recorded_once?({ key: 'a' })).to be(false)              # unfrozen Hash
        expect(recorded_once?(account.new)).to be(false)               # a record
      end
    end

    it 'does not share a mutable with: value between bakes' do
      define_model('DeclCacheMutableParent', token: :string) do
        def token=(value)
          super(value << '!')
        end
      end
      owner = define_model('DeclCacheMutableOwner', name: :string, parent_id: :integer) do
        belongs_to :parent, class_name: 'DeclCacheMutableParent', optional: false
      end
      FactoryBakery.define(owner) { association :parent, with: { token: String.new('a') } }

      tokens = [FactoryBakery.bake(owner).parent.token,
                FactoryBakery.bake(owner).parent.token,
                Thread.new { FactoryBakery.bake(owner).parent.token }.value]

      # Each bake declares its own string, which this setter normalizes in
      # place (twice per bake, like any declared override that a rebuild
      # re-applies). A value shared between bakes would keep growing instead:
      # the second and later bakes would see 'a!!!!' and worse.
      expect(tokens).to all(eq('a!!'))
    end
  end
end
