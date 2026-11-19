# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/sequel_database'

# The public API (define, traits, named factories, overrides) works on
# Sequel::Model classes exactly as on the default mapper's models, plus the
# association guard-rails: foreign keys of many_to_one associations are read
# from the reflections but never auto-built.
RSpec.describe 'Sequel mapper public API', :sequel_mapper do
  include DefineSequelModelMacros

  let!(:model) do
    define_sequel_model('SeqGadget', name: :string, body: :text, rating: :integer)
  end

  it 'bakes a class with no definition at all' do
    gadget = FactoryBakery.bake(model)

    expect(gadget.name).to be_a(String)
    expect(gadget.body).to be_a(String)
    expect(gadget.rating).to be_an(Integer)
  end

  it 'applies definitions, traits and call-site overrides in precedence order' do
    FactoryBakery.define(model) do
      name { 'Ada' }

      trait :grumpy do
        body { 'Bah humbug' }
      end
    end

    gadget = FactoryBakery.bake(model, :grumpy, name: 'Grace')

    expect(gadget.name).to eq('Grace')
    expect(gadget.body).to eq('Bah humbug')
    expect(gadget.rating).to be_an(Integer)
  end

  it 'raises a clear error for an unknown trait' do
    FactoryBakery.define(model) { name { 'Ada' } }

    expect { FactoryBakery.bake(model, :nope) }
      .to raise_error(FactoryBakery::Error, /Trait :nope/)
  end

  it 'bakes named factories bound to a Sequel class' do
    FactoryBakery.define(:seq_thing, klass: model) do
      name { 'Gizmo' }
    end

    expect(FactoryBakery.bake(:seq_thing).name).to eq('Gizmo')
  end

  it 'persists a definition-baked record through bake!' do
    FactoryBakery.define(model) do
      name { 'Persisted Ada' }
    end

    gadget = FactoryBakery.bake!(model)

    expect(gadget).not_to be_new
    expect(model.count).to eq(1)
    expect(model.first.name).to eq('Persisted Ada')
  end

  describe 'association guard-rails' do
    let!(:owner_model) do
      define_sequel_model(
        'SeqOrder',
        name: :string,
        seq_customer_id: :integer,
        seq_clerk_id: :integer
      ) do
        many_to_one :seq_customer
      end
    end

    it 'guards the primary key and declared association keys, not bare _id-like columns' do
      guards = FactoryBakery::MapperRegistry.guard_columns(owner_model)

      expect(guards.names).to contain_exactly('id', 'seq_customer_id')
      expect(guards.counter_names).to be_empty
    end

    it 'leaves guarded foreign keys nil on a plain bake' do
      order = FactoryBakery.bake(owner_model)

      expect(order.seq_customer_id).to be_nil
    end

    it 'still fills a plain _id-like column that backs no association' do
      order = FactoryBakery.bake(owner_model)

      expect(order.seq_clerk_id).to be_an(Integer)
    end

    it 'accepts an explicit foreign key override' do
      order = FactoryBakery.bake(owner_model, seq_customer_id: 7)

      expect(order.seq_customer_id).to eq(7)
    end

    it 'groups an association name with its foreign key columns' do
      groups = FactoryBakery::MapperRegistry.alias_groups(owner_model)

      expect(groups['seq_customer']).to eq(%w[seq_customer seq_customer_id])
      expect(groups['seq_customer_id']).to eq(%w[seq_customer seq_customer_id])
      expect(FactoryBakery::MapperRegistry.belongs_to_association_names(owner_model))
        .to eq(['seq_customer'])
    end
  end
end
