# frozen_string_literal: true

require 'spec_helper'

# W4 / issue #44: PostgreSQL array columns (t.string "tags", array: true)
# used to be routed to StringFiller, so model code calling #map on the value
# crash-baked. These specs cover the normalized constraint marker, the pure
# ArrayFiller generator, routing, the real PG round trip, and the recorded
# CustomFilter.context failure class.
RSpec.describe 'array column filler (issue #44)' do
  include DefineConstantMacros

  # Portable unit level: no framework reading happens in the core, so the
  # normalized ConstraintSet can be supplied directly.
  describe 'ArrayFiller (pure generator)' do
    def stub_constraints(**attrs)
      constraints = FactoryBakery::ConstraintSet.new(
        **{
          model_class: Object,
          attr_name: 'tags',
          type: :array,
          array_element_type: :string
        }.merge(attrs)
      )
      allow(FactoryBakery::ConstraintSet).to receive(:for).with(Object, 'tags').and_return(constraints)
      constraints
    end

    def build_filler
      FactoryBakery::AttributeFillers::ArrayFiller.new(Object, 'tags')
    end

    it 'produces a small Array of plausible strings for a :string element hint' do
      stub_constraints(array_element_type: :string)
      filler = build_filler

      20.times do
        value = filler.call
        expect(value).to be_a(Array)
        expect(value.length).to be_between(1, 3)
        expect(value).to all(be_a(String))
        expect(value).to all(satisfy { |element| !element.empty? })
      end
    end

    it 'produces integers for an :integer element hint' do
      stub_constraints(array_element_type: :integer)
      filler = build_filler

      value = filler.call

      expect(value).to be_a(Array)
      expect(value).to all(be_a(Integer))
    end

    it 'produces floats for a :float element hint' do
      stub_constraints(array_element_type: :float)
      filler = build_filler

      value = filler.call

      expect(value).to be_a(Array)
      expect(value).to all(be_a(Float))
    end

    it 'honors absence with nil' do
      stub_constraints(absence_required: true)
      expect(build_filler.call).to be_nil
    end

    it 'picks a whole Array from an inclusion set whose members are arrays' do
      allowed = [%w[alpha beta], %w[gamma]]
      stub_constraints(allowed_values: allowed)
      filler = build_filler

      expect(allowed).to include(filler.call)
    end

    it 'regenerates an array-shaped value on exclusion collisions' do
      stub_constraints(forbidden_values: [['alpha'], %w[alpha alpha], %w[alpha alpha alpha]])
      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'beta')
      filler = build_filler
      allow(filler).to receive(:rand).and_return(1)

      value = filler.call

      expect(value).to be_a(Array)
      expect(value).to eq(['beta'])
    end

    it 'raises a contextual exhaustion error after bounded regeneration' do
      stub_constraints(forbidden_values: [['alpha'], %w[alpha alpha], %w[alpha alpha alpha]])
      allow(FFaker::Lorem).to receive(:word).and_return('alpha')
      filler = build_filler
      allow(filler).to receive(:rand).and_return(1)

      expect { filler.call }
        .to raise_error(FactoryBakery::Error, /Object#tags.*exclusion after 10 attempts/)
    end

    it 'returns a fresh Array on every call so uniqueness regeneration stays array-shaped' do
      stub_constraints(column_backed: true, column_backed_target: true)
      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'beta')
      filler = build_filler
      allow(filler).to receive(:rand).and_return(1)

      first = filler.call
      second = filler.call

      expect(first).to eq(['alpha'])
      expect(second).to eq(['beta'])
      expect(first).not_to equal(second)
    end
  end

  describe 'routing' do
    it 'routes a normalized :array column to ArrayFiller without any framework reads' do
      constraints = FactoryBakery::ConstraintSet.new(
        model_class: Object, attr_name: 'tags', type: :array,
        array_element_type: :string, column_backed: true, column_backed_target: true
      )
      allow(FactoryBakery::ConstraintSet).to receive(:for).with(Object, 'tags').and_return(constraints)

      filler = FactoryBakery::AttributeFillers::FillerSelector.new(Object, 'tags').call

      expect(filler).to be_a(FactoryBakery::AttributeFillers::ArrayFiller)
    end

    it 'keeps non-PostgreSQL array-ish columns on their adapter-native filler' do
      skip 'non-PostgreSQL adapters only' if DatabaseSupport.postgresql?

      create_table(:legacy_array_columns) do |table|
        DatabaseSupport.add_array_column(table, :tags)
      end
      model = define_class('LegacyArrayColumn', ActiveRecord::Base)

      record = FactoryBakery.bake(model, fill_optional: true)

      # SQLite/MySQL have no array type, so the shared helper translates the
      # column to JSON; the JsonFiller (not ArrayFiller) handles it.
      expect(record.tags).to be_a(Hash)
    end
  end

  describe 'constraint reading for Sequel (best effort)' do
    before(:all) { require 'factory_bakery/sequel/constraint_reader' }

    it 'maps a PG-style array schema entry to :array with an element hint' do
      model = double('sequel model', db_schema: {
                       tags: { type: :array, db_type: 'character varying[]' },
                       counts: { type: :array, db_type: 'integer[]' },
                       plain: { type: :string, db_type: 'character varying' }
                     })
      reader = FactoryBakery::Sequel::ConstraintReader

      tags = reader.call(model, 'tags')
      counts = reader.call(model, 'counts')
      plain = reader.call(model, 'plain')

      expect(tags.type).to eq(:array)
      expect(tags.array_element_type).to eq(:string)
      expect(counts.array_element_type).to eq(:integer)
      expect(plain.type).to eq(:string)
      expect(plain.array_element_type).to be_nil
    end
  end

  describe 'constraint reading on PostgreSQL' do
    before { skip 'PostgreSQL array columns required' unless DatabaseSupport.postgresql? }

    it 'marks array columns as type :array with an element-type hint' do
      model = define_model(
        'ArrayColumnMetadata',
        tags: { type: :string, array: true },
        counts: { type: :integer, array: true },
        title: :string
      )

      tags = FactoryBakery::ConstraintSet.for(model, 'tags')
      counts = FactoryBakery::ConstraintSet.for(model, 'counts')
      title = FactoryBakery::ConstraintSet.for(model, 'title')

      expect(tags.type).to eq(:array)
      expect(tags.array_element_type).to eq(:string)
      expect(counts.type).to eq(:array)
      expect(counts.array_element_type).to eq(:integer)
      expect(title.type).to eq(:string)
      expect(title.array_element_type).to be_nil
    end
  end

  describe 'bake on PostgreSQL' do
    before { skip 'PostgreSQL array columns required' unless DatabaseSupport.postgresql? }

    it 'fills string and integer array columns with plausible Arrays' do
      model = define_model(
        'BakedArrayColumns',
        tags: { type: :string, array: true },
        counts: { type: :integer, array: true }
      )

      record = FactoryBakery.bake(model)

      expect(record.tags).to be_a(Array)
      expect(record.tags).to all(be_a(String))
      expect(record.counts).to be_a(Array)
      expect(record.counts).to all(be_a(Integer))
    end

    it 'persists and reloads the Array with its elements intact' do
      model = define_model(
        'RoundTripArrayColumn',
        tags: { type: :string, array: true },
        counts: { type: :integer, array: true }
      )

      record = FactoryBakery.bake!(model)
      reloaded = model.find(record.id)

      expect(record).to be_persisted
      expect(reloaded.tags).to be_a(Array)
      expect(reloaded.tags).to eq(record.tags)
      expect(reloaded.tags).to all(be_a(String))
      expect(reloaded.counts).to eq(record.counts)
      expect(reloaded.counts).to all(be_a(Integer))
    end

    it 'regenerates an array-shaped value on uniqueness collision' do
      model = define_model('UniqueArrayPayload', tags: { type: :string, array: true }) do
        validates :tags, uniqueness: true
      end
      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'beta')

      first = FactoryBakery.bake!(model)
      second = FactoryBakery.bake!(model)

      expect(first.tags).to be_a(Array)
      expect(second.tags).to be_a(Array)
      expect(second.tags).not_to eq(first.tags)
      expect(second).to be_valid
      expect(model.count).to eq(2)
    end

    it 'bakes the Discourse/Mastodon CustomFilter.context class (presence + #map validator)' do
      model = define_model('CustomFilter', context: { type: :string, array: true }) do
        validates :context, presence: true
        validate :context_entries_are_strings

        def context_entries_are_strings
          return if context.blank?

          errors.add(:context, 'entries must be strings') unless context.map { |entry| entry.is_a?(String) }.all?
        end
      end

      expect { FactoryBakery.bake(model) }.not_to raise_error
      record = FactoryBakery.bake(model)

      expect(record.context).to be_a(Array)
      expect(record.context).to all(be_a(String))
      expect(record).to be_valid
    end
  end
end
