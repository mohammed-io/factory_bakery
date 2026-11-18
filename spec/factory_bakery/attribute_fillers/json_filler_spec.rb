# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'json/jsonb column filler (issue #39)' do
  include DefineConstantMacros

  describe 'bake' do
    it 'fills a json column with a JSON-serializable Hash instead of a String' do
      model = define_model('JsonPayload', payload: :json)

      record = FactoryBakery.bake(model)

      expect(record).to be_new_record
      expect(record.payload).to be_a(Hash)
      expect(record.payload).not_to be_a(String)
      expect(JSON.parse(JSON.generate(record.payload))).to eq(record.payload)
    end

    it 'fills a jsonb column with a Hash' do
      model = define_model('JsonbPayload', payload: :jsonb)

      record = FactoryBakery.bake(model)

      expect(record.payload).to be_a(Hash)
      expect(JSON.parse(JSON.generate(record.payload))).to eq(record.payload)
    end

    it 'generates shallow structures with a variety of JSON value types' do
      model = define_model('VariedJsonPayload', payload: :json)

      record = FactoryBakery.bake(model)
      payload = record.payload

      expect(payload.keys).to all(be_a(String))
      expect(payload.values).to include(a_kind_of(String), a_kind_of(Integer), a_kind_of(Float),
                                        a_kind_of(Array), a_kind_of(Hash))
      expect(payload.values.any? { |value| [true, false].include?(value) }).to be(true)
      expect(payload.values.any? do |value|
        value.is_a?(Hash) && value.keys.all? { |key| key.is_a?(String) }
      end).to be(true)
    end
  end

  describe 'bake!' do
    it 'persists and reloads the Hash with its structure intact' do
      model = define_model('JsonDocument', payload: :json)

      record = FactoryBakery.bake!(model)
      reloaded = model.find(record.id)

      expect(record).to be_persisted
      expect(record.payload).to be_a(Hash)
      expect(reloaded.payload).to eq(record.payload)
      expect(reloaded.payload.values).to include(a_kind_of(Hash), a_kind_of(Array))
    end

    it 'hands a Hash to a Hash-expecting custom validator (Discourse AppearanceChange failure class)' do
      model = define_model('AppearanceChange', site_settings: :json) do
        validate :only_supported_site_settings

        def only_supported_site_settings
          site_settings.keys # a String raises NoMethodError here
        end
      end

      record = FactoryBakery.bake!(model)

      expect(record).to be_persisted
      expect(record.site_settings).to be_a(Hash)
      expect(model.find(record.id).site_settings).to eq(record.site_settings)
    end
  end

  describe 'validators on json columns' do
    it 'picks a value from an inclusion array of Hashes' do
      options = [{ 'tier' => 'basic' }, { 'tier' => 'pro' }]
      model = define_model('TieredPayload', payload: :json) do
        validates :payload, inclusion: { in: options }
      end

      record = FactoryBakery.bake!(model)

      expect(options).to include(record.payload)
      expect(record).to be_valid
    end

    it 'avoids every Hash in an exclusion array' do
      forbidden = { 'forbidden' => true }
      model = define_model('ExcludedPayload', payload: :json) do
        validates :payload, exclusion: { in: [forbidden] }
      end

      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'beta')

      record = FactoryBakery.bake!(model)

      expect(record.payload).to be_a(Hash)
      expect(record.payload).not_to eq(forbidden)
      expect(record).to be_valid
    end
  end

  describe 'uniqueness' do
    it 'regenerates a Hash-shaped value on collision' do
      # PostgreSQL's `json` type has no equality operator, so the uniqueness
      # validator needs `jsonb` there (and plain `json` on the other adapters).
      model = define_model('UniqueJsonPayload', payload: DatabaseSupport.json_type) do
        validates :payload, uniqueness: true
      end

      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'alpha', 'beta')

      first = FactoryBakery.bake!(model)
      second = FactoryBakery.bake!(model)

      expect(first.payload).to be_a(Hash)
      expect(second.payload).to be_a(Hash)

      if DatabaseSupport.mysql?
        # MySQL has no `JSON = <bound string>` operator (it needs CAST(... AS
        # JSON)), so ActiveRecord's uniqueness validator cannot observe a
        # duplicate JSON payload and there is no collision to regenerate from.
        # Documented adapter difference from A18's matrix run.
        expect(second).to be_persisted
      else
        expect(second.payload).not_to eq(first.payload)
        expect(second).to be_valid
      end
      expect(model.count).to eq(2)
    end
  end

  describe 'routing of other column types' do
    it 'leaves text, binary and string columns on the string filler' do
      model = define_model('NonJsonPayload', body: :text, blob: :binary, title: :string)

      record = FactoryBakery.bake(model)

      expect(record.body).to be_a(String)
      expect(record.blob).to be_a(String)
      expect(record.title).to be_a(String)
      expect([record.body, record.blob, record.title].any? { |value| value.is_a?(Hash) }).to be(false)
    end
  end
end
