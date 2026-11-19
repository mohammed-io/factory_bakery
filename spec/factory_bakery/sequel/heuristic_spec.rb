# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/sequel_database'

# Heuristic bakes of Sequel::Model classes driven by db_schema column types:
# the mapper normalizes each Sequel schema type into the same core type the
# default mapper produces for its own models, so the shared generators route
# and fill unchanged.
RSpec.describe 'Sequel mapper column heuristics', :sequel_mapper do
  include DefineSequelModelMacros

  let!(:model) do
    define_sequel_model(
      'SeqWidget',
      name: { type: :string, size: 60 },
      body: :text,
      count: { type: :integer, null: false, default: 0 },
      age: { type: :integer, null: false },
      ratio: :float,
      price: { type: :decimal, size: [10, 2] },
      shipped_on: :date,
      published_at: :datetime,
      alarm_at: :time,
      active: :boolean,
      tags: :json
    )
  end

  it 'generates a type-appropriate value for every column type' do
    widget = FactoryBakery.bake(model)

    expect(widget.name).to be_a(String)
    expect(widget.name.length).to be <= 60
    expect(widget.body).to be_a(String)
    expect(widget.age).to be_an(Integer)
    expect(widget.ratio).to be_a(Float)
    expect(widget.price).to be_a(BigDecimal)
    expect(widget.shipped_on).to be_a(Date)
    expect(widget.published_at).to be_kind_of(Time)
    expect(widget.alarm_at).to be_kind_of(Time)
    expect([true, false]).to include(widget.active)
  end

  it 'fills a NOT NULL column without a default with a non-nil value' do
    widget = FactoryBakery.bake(model)

    expect(widget.age).not_to be_nil
  end

  it 'fills a json column with a JSON-serializable Hash' do
    widget = FactoryBakery.bake(model)

    expect(widget.tags).to be_a(Hash)
    expect(widget.tags.keys).to all(be_a(String))
  end

  it 'exposes the schema limits the generators consume' do
    constraints = FactoryBakery::ConstraintSet.for(model, 'name')

    expect(constraints.db_limit).to eq(60)
    expect(constraints.column_backed).to be(true)
    expect(constraints.column_backed_target).to be(true)
    expect(constraints.type).to eq(:string)
  end

  it 'exposes precision and scale parsed from a numeric db_type' do
    constraints = FactoryBakery::ConstraintSet.for(model, 'price')

    expect(constraints.type).to eq(:decimal)
    expect(constraints.precision).to eq(10)
    expect(constraints.scale).to eq(2)
  end

  it 'leaves the primary key alone and excludes it from the universe' do
    widget = FactoryBakery.bake(model)

    expect(widget.id).to be_nil
    expect(FactoryBakery::MapperRegistry.attribute_universe(model)).not_to include('id')
  end

  it 'keeps database defaults instead of generating over them' do
    defaulted = define_sequel_model(
      'SeqDefaulted',
      title: :string,
      status: { type: :string, null: false, default: 'draft' }
    )

    record = FactoryBakery.bake!(defaulted)

    expect(defaulted.count).to eq(1)
    expect(record.reload.status).to eq('draft')
  end
end
