# frozen_string_literal: true

require 'spec_helper'
require 'factory_bakery/associations'

# Association declarations are recorded with the definition that declares them
# (ADR-0008) and replayed to every bake. Observable contract: the definition
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
end
