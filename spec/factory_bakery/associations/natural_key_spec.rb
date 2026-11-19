# frozen_string_literal: true

require 'spec_helper'
require 'factory_bakery/associations'

# Public-API behavior of issue #54: a belongs_to keyed on a natural key is
# ordinary data, not a reference to a freshly built parent's id. Assertions
# only touch bake/bake!, model attributes and validity.
RSpec.describe 'FactoryBakery associations: natural-key belongs_to' do
  before do
    FactoryBakery.reset_plugins!
    FactoryBakery.register_plugin(FactoryBakery::Associations::Plugin)
    FactoryBakery::Associations.mode = :required_only
  end

  after do
    FactoryBakery.reset_plugins!
    FactoryBakery::Associations.reset_configuration!
  end

  it 'fills the column of an optional natural-key FK without building the parent' do
    define_model('NatOptInstance', domain: { type: :string, null: false })
    note = define_model('NatOptNote', domain: { type: :string, null: false }) do
      belongs_to :instance, class_name: 'NatOptInstance',
                            foreign_key: :domain, primary_key: :domain, optional: true
    end

    record = FactoryBakery.bake(note)

    expect(record.domain).to be_a(String)
    expect(record.domain).not_to be_empty
    expect(record.instance).to be_nil
    expect(record).to be_valid
    expect(Object.const_get('NatOptInstance').count).to eq(0)
  end

  it 'builds a required natural-key parent whose key equals the child FK' do
    define_model('NatReqBlock', domain: { type: :string, null: false })
    note = define_model('NatReqNote', domain: { type: :string, null: false }) do
      belongs_to :domain_block, class_name: 'NatReqBlock',
                                foreign_key: :domain, primary_key: :domain, optional: false
    end

    record = FactoryBakery.bake(note)

    expect(record.domain_block).to be_a(Object.const_get('NatReqBlock'))
    expect(record.domain_block.domain).to eq(record.domain)
    expect(record).to be_valid
  end

  it 'keeps three required natural-key parents sharing one FK column consistent' do
    define_model('NatSharedBlock', domain: { type: :string, null: false })
    define_model('NatSharedAllow', domain: { type: :string, null: false })
    define_model('NatSharedUnavailable', domain: { type: :string, null: false })
    instance = define_model('NatSharedInstance', domain: { type: :string, null: false }) do
      belongs_to :domain_block, class_name: 'NatSharedBlock',
                                foreign_key: :domain, primary_key: :domain, optional: false
      belongs_to :domain_allow, class_name: 'NatSharedAllow',
                                foreign_key: :domain, primary_key: :domain, optional: false
      belongs_to :unavailable_domain, class_name: 'NatSharedUnavailable',
                                      foreign_key: :domain, primary_key: :domain, optional: false
    end

    record = FactoryBakery.bake(instance)

    keys = [record.domain_block.domain, record.domain_allow.domain, record.unavailable_domain.domain]
    expect(keys).to eq([record.domain] * 3)
    expect(record).to be_valid
  end

  it 'propagates a call-site FK override to every built parent' do
    define_model('NatOverrideBlock', domain: { type: :string, null: false })
    define_model('NatOverrideAllow', domain: { type: :string, null: false })
    instance = define_model('NatOverrideInstance', domain: { type: :string, null: false }) do
      belongs_to :domain_block, class_name: 'NatOverrideBlock',
                                foreign_key: :domain, primary_key: :domain, optional: false
      belongs_to :domain_allow, class_name: 'NatOverrideAllow',
                                foreign_key: :domain, primary_key: :domain, optional: false
    end

    record = FactoryBakery.bake(instance, domain: 'x.test')

    expect(record.domain).to eq('x.test')
    expect([record.domain_block.domain, record.domain_allow.domain]).to eq(['x.test', 'x.test'])
    expect(record).to be_valid
  end

  it 'persists a natural-key graph under bake! with consistent keys' do
    define_model('NatPersistBlock', domain: { type: :string, null: false })
    instance = define_model('NatPersistInstance', domain: { type: :string, null: false }) do
      belongs_to :domain_block, class_name: 'NatPersistBlock',
                                foreign_key: :domain, primary_key: :domain, optional: false
    end

    record = FactoryBakery.bake!(instance)

    expect(record).to be_persisted
    expect(record.domain_block).to be_persisted
    expect(record.domain_block.domain).to eq(record.domain)
  end

  it 'still treats a NOT NULL id-keyed FK as required when the association is optional' do
    define_model('NatIdTeam', name: :string)
    player = define_model('NatIdPlayer', team_id: { type: :integer, null: false }) do
      belongs_to :team, class_name: 'NatIdTeam', optional: true
    end

    record = FactoryBakery.bake(player)

    expect(record.team).to be_a(Object.const_get('NatIdTeam'))
    expect(record.team).to be_new_record
  end

  it 'does not build natural-key parents in :none mode' do
    define_model('NatNoneBlock', domain: { type: :string, null: false })
    note = define_model('NatNoneNote', domain: { type: :string, null: false }) do
      belongs_to :domain_block, class_name: 'NatNoneBlock',
                                foreign_key: :domain, primary_key: :domain, optional: false
    end

    FactoryBakery::Associations.mode = :none
    record = FactoryBakery.bake(note)

    expect(record.domain).to be_a(String)
    expect(record.domain_block).to be_nil
  end

  it 'lets an explicit association override suppress the natural-key build' do
    define_model('NatExplicitBlock', domain: { type: :string, null: false })
    note = define_model('NatExplicitNote', domain: { type: :string, null: false }) do
      belongs_to :domain_block, class_name: 'NatExplicitBlock',
                                foreign_key: :domain, primary_key: :domain, optional: false
    end
    parent = Object.const_get('NatExplicitBlock').new(domain: 'explicit.test')

    record = FactoryBakery.bake(note, domain_block: parent)

    expect(record.domain_block).to equal(parent)
    expect(record.domain).to eq('explicit.test')
  end
end
