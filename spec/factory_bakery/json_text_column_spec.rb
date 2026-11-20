# frozen_string_literal: true

require 'spec_helper'

# A PostgreSQL expression index can force a plain text column to hold JSON:
# `((data)::jsonb ->> 'username')` is evaluated on every insert, so a non-JSON
# string is rejected with "invalid input syntax for type json" (Discourse's
# `notifications.data`, a varchar(1000)).
#
# SQLite cannot create such an index (`json_extract` in an index expression is
# not the same SQL shape), so the detector is unit-tested on the real SQL in
# `spec/factory_bakery/active_record_mapper/json_cast_spec.rb`. Here the mapper
# is driven with a stub that answers the way a PostgreSQL catalog would, which
# pins the behaviour the value side needs: the string filler emits parseable
# JSON for a text column an index casts.
RSpec.describe 'JSON stored in a text column (index-cast)' do
  include DefineConstantMacros

  # A column the mapper reports as cast by a table index, the way
  # `Mapper#json_text?` would on PostgreSQL.
  def stub_json_cast(klass, columns)
    allow(FactoryBakery::MapperRegistry).to receive(:json_text?) do |target, attr_name|
      target == klass && columns.include?(attr_name.to_s)
    end
  end

  before do
    FactoryBakery.reset_plugins!
  end

  after do
    FactoryBakery.reset_plugins!
  end

  it 'emits a JSON document a PostgreSQL cast accepts for a text column' do
    model = define_model('JsonCastNote', data: { type: :string, limit: 1000, null: false })
    stub_json_cast(model, %w[data])

    record = FactoryBakery.bake(model)

    expect(record.data).to be_a(String)
    expect(record).to be_valid
    expect(record.data.length).to be <= 1000
    expect { JSON.parse(record.data) }.not_to raise_error
  end

  it 'fills the column when filling optional attributes is asked for' do
    model = define_model('JsonCastOptional', data: { type: :string, limit: 1000 })
    stub_json_cast(model, %w[data])

    record = FactoryBakery.bake(model, fill_optional: true)

    expect(record.data).to be_a(String)
    expect { JSON.parse(record.data) }.not_to raise_error
  end

  it 'still emits JSON when a presence validator also applies' do
    model = define_model('JsonCastPresence', data: { type: :string, limit: 1000, null: false }) do
      validates :data, presence: true
    end
    stub_json_cast(model, %w[data])

    record = FactoryBakery.bake(model)

    expect(record).to be_valid
    expect(record.data).to match(/\A\{.*\}\z/m)
    expect { JSON.parse(record.data) }.not_to raise_error
  end

  it 'generates JSON for both a cast column and its attribute alias' do
    model = define_model('JsonCastAliasedNote', data: { type: :string, null: false }) do
      alias_attribute :payload, :data
    end
    connection = model.connection
    index = ActiveRecord::ConnectionAdapters::IndexDefinition.new(
      model.table_name, 'data_username', false, "(((data)::jsonb ->> 'username'::text))"
    )
    allow(connection).to receive(:indexes).with(model.table_name).and_return([index])

    record = FactoryBakery.bake!(model).reload

    expect(JSON.parse(record.data)).to be_a(Hash)
    expect(JSON.parse(record.payload)).to be_a(Hash)
  end

  it 'leaves a text column no index casts alone' do
    model = define_model('JsonCastPlain', data: { type: :string, limit: 1000, null: false })
    stub_json_cast(model, [])

    record = FactoryBakery.bake(model)

    expect(record).to be_valid
    expect(record.data).to be_a(String)
  end
end
