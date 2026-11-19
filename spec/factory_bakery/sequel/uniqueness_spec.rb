# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/sequel_database'

# Uniqueness enforcement on Sequel classes: the flag comes from a stored
# uniqueness reflection OR from a single-column unique index on the model's
# dataset schema, and the check queries the model's own dataset.
RSpec.describe 'Sequel mapper uniqueness enforcement', :sequel_mapper do
  include DefineSequelModelMacros

  describe 'a stored uniqueness reflection' do
    let!(:model) do
      define_sequel_model('SeqUnique', code: { type: :string, null: false }) do
        plugin :validation_class_methods
        validates_uniqueness_of :code
      end
    end

    it 'flags the attribute as uniqueness-validated' do
      expect(FactoryBakery::MapperRegistry).to be_uniqueness_validated(model, 'code')
      expect(FactoryBakery::MapperRegistry).not_to be_uniqueness_validated(model, 'id')
    end

    it 'regenerates on collision and produces distinct persisted records' do
      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'alpha', 'beta', 'gamma')

      first = FactoryBakery.bake!(model)
      second = FactoryBakery.bake!(model)

      expect(first.code).to eq('alpha')
      expect(second.code).to eq('beta')
      expect(model.count).to eq(2)
    end

    it 'sees values inserted by other writes, not just by this bake' do
      model.create(code: 'alpha')
      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'beta')

      record = FactoryBakery.bake!(model)

      expect(record.code).to eq('beta')
      expect(model.count).to eq(2)
    end

    it 'excludes the record itself from the taken check when updating' do
      record = FactoryBakery.bake!(model)

      expect(FactoryBakery::MapperRegistry.uniqueness_check(record, 'code', record.code)).to be(false)
    end

    it 'treats nil as not taken, mirroring the model-level validators' do
      record = FactoryBakery.bake(model)

      expect(FactoryBakery::MapperRegistry.uniqueness_check(record, 'code', nil)).to be(false)
    end

    it 'raises a clear error naming the attribute when the value space is exhausted' do
      exhausted = define_sequel_model(
        'SeqExhausted',
        code: { type: :string, null: false }
      ) do
        plugin :validation_class_methods
        validates_inclusion_of :code, in: ['FIXED']
        validates_uniqueness_of :code
      end

      FactoryBakery.bake!(exhausted)

      expect { FactoryBakery.bake!(exhausted) }
        .to raise_error(FactoryBakery::Error, /SeqExhausted#code.*FIXED.*uniqueness/m)

      expect(exhausted.count).to eq(1)
    end
  end

  describe 'a unique index without a model-level validation' do
    let!(:model) do
      define_sequel_model('SeqIndexedUnique', slug: { type: :string, null: false, unique: true })
    end

    it 'flags the column through the dataset schema' do
      expect(FactoryBakery::MapperRegistry).to be_uniqueness_validated(model, 'slug')
    end

    it 'regenerates on collision exactly like a declared validation' do
      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'alpha', 'beta')

      first = FactoryBakery.bake!(model)
      second = FactoryBakery.bake!(model)

      expect(first.slug).to eq('alpha')
      expect(second.slug).to eq('beta')
      expect(model.count).to eq(2)
    end
  end

  describe 'a composite unique index' do
    let!(:model) do
      define_sequel_model('SeqCompositeUnique',
                          a: :string, b: :string,
                          _index: { columns: %i[a b], unique: true })
    end

    it 'does not flag either single column as uniqueness-validated' do
      expect(FactoryBakery::MapperRegistry).not_to be_uniqueness_validated(model, 'a')
      expect(FactoryBakery::MapperRegistry).not_to be_uniqueness_validated(model, 'b')
    end
  end
end
