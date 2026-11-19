# frozen_string_literal: true

require 'spec_helper'

# Issue #58: name- and title-like values are what apps derive slugs and
# normalized keys from, and that derivation is invisible to validator-based
# uniqueness. Discourse's Category derives `slug` from `name`; a bare lorem
# word ("voluptas") collided with rows from earlier bakes.
RSpec.describe 'entropy for name-like values (issue #58)' do
  include DefineConstantMacros

  around do |example|
    srand(58_000)
    example.run
  ensure
    srand
  end

  describe 'distinctness across bakes' do
    let!(:named) { define_model('EntropyNamed58', name: :string) }

    it 'produces at least 999 distinct names in 1000 bakes' do
      names = Array.new(1000) { FactoryBakery.bake(named, fill_optional: true).name }

      expect(names.uniq.length).to be >= 999
    end
  end

  describe 'a model deriving a unique slug from the name' do
    let!(:category) do
      define_model('EntropyCategory58', name: :string, slug: :string) do
        before_validation { self.slug = name.to_s.parameterize }
        validate :slug_is_unique

        def slug_is_unique
          return if slug.blank? || self.class.where(slug: slug).where.not(id: id).none?

          errors.add(:slug, 'has already been taken')
        end
      end
    end

    it 'bakes 200 valid persisted records in a row' do
      records = Array.new(200) { FactoryBakery.bake!(category, fill_optional: true) }

      expect(records).to all(be_persisted)
      expect(records).to all(be_valid)
      expect(records.map(&:slug).uniq.length).to eq(200)
    end
  end

  describe 'length limits' do
    let!(:short_named) { define_model('ShortEntropyName58', name: { type: :string, limit: 10 }) }

    it 'keeps the suffix and stays within the db limit while staying distinct' do
      names = Array.new(1000) { FactoryBakery.bake(short_named, fill_optional: true).name }

      expect(names).to all(satisfy { |name| name.length <= 10 })
      expect(names.uniq.length).to be >= 999
    end
  end

  describe 'value shapes' do
    it 'appends entropy to name, title, slug, key and label values' do
      columns = { name: :string, title: :string, slug: :string, key: :string, label: :string }
      model = define_model('EntropyShapes58', columns)
      record = FactoryBakery.bake(model, fill_optional: true)

      expect(record.name).to match(/\A[a-zA-Z]+\s+[a-zA-Z].*\s\d{6}\z/)
      # Issue #59 made titles short sentences; the #58 entropy suffix still
      # comes last, after at least four distinct words.
      expect(record.title).to match(/\A[A-Z][a-z]+(?: [a-z]+){3,} \d{6}\z/)
      expect(record.slug).to match(/\A[a-z]+-\d{6}\z/)
      expect(record.key).to match(/\A[a-z]+-\d{6}\z/)
      expect(record.label).to match(/\A[a-z]+ \d{6}\z/)
    end

    it 'leaves identifier-like names on their own shape' do
      model = define_model('EntropyUsername58', username: :string)

      expect(FactoryBakery.bake(model, fill_optional: true).username).to match(/\A[a-z][a-z0-9_]{2,19}\z/)
    end

    it 'keeps a declared format over the entropy suffix' do
      model = define_model('FormattedEntropyName58', name: :string) do
        validates :name, format: { with: /\A[a-z]+\z/ }
      end

      expect(FactoryBakery.bake(model, fill_optional: true).name).to match(/\A[a-z]+\z/)
    end
  end

  describe 'seeded determinism' do
    let!(:model) { define_model('SeededEntropy58', name: :string, title: :string, slug: :string) }

    before do
      allow(FFaker::Name).to receive(:name).and_return('John Smith')
      allow(FFaker::Lorem).to receive(:word).and_return('voluptas')
    end

    it 'produces the same values when the seed is repeated' do
      srand(20_261_119)
      first = FactoryBakery.bake(model, fill_optional: true)
      srand(20_261_119)
      second = FactoryBakery.bake(model, fill_optional: true)

      expect([second.name, second.title, second.slug]).to eq([first.name, first.title, first.slug])
    end
  end
end
