# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/sequel_database'

# The persistence contract over the Sequel adapter: bake stays database-free,
# bake! saves through the model's own save (which raises on validation
# failure) inside a savepoint-capable transaction on the model's database.
#
# Declaration blocks capture their models in local variables first: inside
# a definition block a bare `sibling` call would be captured as an attribute
# declaration by the builder's method_missing instead of resolving the
# let! accessor.
RSpec.describe 'Sequel mapper persistence contract', :sequel_mapper do
  include DefineSequelModelMacros

  let!(:model) do
    define_sequel_model(
      'SeqPersisted',
      code: { type: :string, null: false },
      count: { type: :integer, null: false, default: 0 },
      ratio: :float,
      price: { type: :decimal, size: [10, 2] },
      shipped_on: :date,
      published_at: :datetime,
      active: :boolean
    ) do
      plugin :validation_class_methods
      validates_uniqueness_of :code
    end
  end

  def define_nested_bake_declaration!(sibling_model)
    widget_model = model
    FactoryBakery.define(widget_model) do
      other { FactoryBakery.bake!(sibling_model) }
    end
  end

  def define_nested_unsaved_declaration!(sibling_model)
    widget_model = model
    FactoryBakery.define(widget_model) do
      other { FactoryBakery.bake(sibling_model) }
    end
  end

  describe 'bake vs bake!' do
    it 'returns an unsaved record and writes nothing' do
      record = FactoryBakery.bake(model)

      expect(record).to be_new
      expect(model.count).to eq(0)
    end

    it 'persists through the model save inside one transaction' do
      record = FactoryBakery.bake!(model, fill_optional: true)

      expect(record).not_to be_new
      expect(model.count).to eq(1)

      reloaded = model.first
      expect(reloaded.code).to eq(record.code)
      expect(reloaded.count).to eq(0)
      expect(reloaded.ratio).to be_a(Float)
      expect(reloaded.price).to be_a(BigDecimal)
      expect(reloaded.shipped_on).to be_a(Date)
      expect(reloaded.published_at).to be_kind_of(Time)
      expect([true, false]).to include(reloaded.active)
    end

    it 'regenerates uniqueness collisions and still persists' do
      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'alpha', 'beta')

      two = [FactoryBakery.bake!(model), FactoryBakery.bake!(model)]

      expect(two.map(&:code)).to eq(%w[alpha beta])
      expect(model.count).to eq(2)
    end
  end

  describe 'atomicity', :savepoints do
    it 'leaves no rows from a nested bake! when the root save fails' do
      sibling_model = define_sequel_model('SeqSibling', name: { type: :string, null: false })
      define_nested_bake_declaration!(sibling_model)
      model.create(code: 'taken')

      expect { FactoryBakery.bake!(model, code: 'taken') }
        .to raise_error(Sequel::ValidationFailed)

      expect(model.count).to eq(1)
      expect(sibling_model.count).to eq(0)
    end

    it 'leaves no rows from a nested bake when the root save fails' do
      sibling_model = define_sequel_model('SeqBakedSibling', name: { type: :string, null: false })
      define_nested_unsaved_declaration!(sibling_model)
      model.create(code: 'taken')

      expect { FactoryBakery.bake!(model, code: 'taken') }
        .to raise_error(Sequel::ValidationFailed)

      expect(model.count).to eq(1)
      expect(sibling_model.count).to eq(0)
    end

    it 'rolls back to a savepoint when the caller rescues inside an outer transaction' do
      sibling_model = define_sequel_model('SeqSavepointSibling', name: { type: :string, null: false })
      define_nested_bake_declaration!(sibling_model)

      model.db.transaction do
        model.create(code: 'dup')

        expect { FactoryBakery.bake!(model, code: 'dup') }
          .to raise_error(Sequel::ValidationFailed)

        expect(model.count).to eq(1)
        expect(sibling_model.count).to eq(0)

        # The outer transaction is still usable after the savepoint rollback.
        model.create(code: 'outer')
      end

      expect(model.count).to eq(2)
      expect(model.select_order_map(:code)).to contain_exactly('dup', 'outer')
    end
  end

  describe 'verify and raise', :savepoints do
    it 'raises IncompletePersistenceError when a declaration leaves a generated record unsaved' do
      sibling_model = define_sequel_model('SeqUnsavedSibling', name: { type: :string, null: false })
      define_nested_unsaved_declaration!(sibling_model)

      expect { FactoryBakery.bake!(model) }
        .to raise_error(FactoryBakery::IncompletePersistenceError, /SeqUnsavedSibling/) { |error|
          expect(error).to be_a(FactoryBakery::Error)
        }

      expect(model.count).to eq(0)
      expect(sibling_model.count).to eq(0)
    end
  end
end
