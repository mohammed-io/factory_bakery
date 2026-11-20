# frozen_string_literal: true

require 'spec_helper'
require 'factory_bakery/active_record_mapper/json_cast'

# The pure SQL reader behind the JSON-in-a-text-column fix. Every pattern is
# pinned on the SQL shapes a real PostgreSQL catalog reports: expression
# indexes, partial indexes, and the `CAST(... AS jsonb)` spelling.
RSpec.describe FactoryBakery::ActiveRecordMapper::JsonCast do
  describe '.columns_in' do
    it 'detects a `col::jsonb` expression index (Discourse notifications.data)' do
      sql = "((data)::jsonb ->> 'username'::text)"

      expect(described_class.columns_in(sql)).to eq(%w[data])
    end

    it 'detects `col::json` and a quoted, schema-qualified cast' do
      expect(described_class.columns_in('"payload"::json')).to eq(%w[payload])
      expect(described_class.columns_in('(payload::pg_catalog.jsonb)')).to eq(%w[payload])
    end

    it 'detects a CAST(col AS json[b]) expression, case-insensitively' do
      expect(described_class.columns_in('CAST(payload AS json)')).to eq(%w[payload])
      expect(described_class.columns_in('cast("payload" AS JSONB)')).to eq(%w[payload])
    end

    it 'reads the cast out of a partial-index predicate' do
      sql = "((payload)::jsonb ->> 'kind'::text)"

      expect(described_class.columns_in('(deleted_at IS NULL)', sql)).to eq(%w[payload])
    end

    it 'names every cast column across several statements, de-duplicated' do
      statements = [
        '((data)::jsonb ->> \'username\')',
        '(lower(email)::text)',
        'CAST(data AS jsonb)'
      ]

      expect(described_class.columns_in(*statements)).to eq(%w[data])
    end

    it 'ignores a plain index column list and a type that merely contains "json"' do
      expect(described_class.columns_in('json_data')).to eq([])
      expect(described_class.columns_in('((json_data)::text)')).to eq([])
      expect(described_class.columns_in(nil)).to eq([])
    end

    it 'does not match a column whose name only ends in a cast-looking suffix' do
      expect(described_class.columns_in('((my_json)::text)')).to eq([])
      expect(described_class.columns_in('((data)::jsonb_extra)')).to eq([])
    end
  end
end
