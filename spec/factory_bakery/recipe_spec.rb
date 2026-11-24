# frozen_string_literal: true

require 'spec_helper'

# `recipe(...).bake(...)` is `bake(...)` and `recipe(...).bake!(...)` is
# `bake!(...)`: two spellings of one bake.
RSpec.describe 'FactoryBakery.recipe' do
  let!(:widget) do
    define_model('RecipeWidget', name: :string, label: :string, size: :integer) do
      validates :name, presence: true
    end
  end

  before do
    FactoryBakery.define(widget) do
      name { 'declared' }
      trait(:labelled) { label { 'tagged' } }
      trait(:big) { size { 100 } }
      trait(:renamed) { name { 'renamed' } }
    end
  end

  it 'bake builds unsaved, like the module bake' do
    record = FactoryBakery.recipe(widget).bake

    expect(record).to be_a(widget)
    expect(record).not_to be_persisted
    expect(record.name).to eq('declared')
  end

  it 'bake! saves, like the module bake!' do
    expect(FactoryBakery.recipe(widget).bake!).to be_persisted
  end

  it 'applies traits given as arguments or chained, in order' do
    expect(FactoryBakery.recipe(widget, :labelled).bake.label).to eq('tagged')
    expect(FactoryBakery.recipe(widget).labelled.big.bake.then { [_1.label, _1.size] }).to eq(['tagged', 100])
    expect(FactoryBakery.recipe(widget).labelled.renamed.bake.name).to eq('renamed')
  end

  it 'applies overrides given to bake, bake!, or the recipe, the latest winning' do
    expect(FactoryBakery.recipe(widget).bake(name: 'late').name).to eq('late')
    expect(FactoryBakery.recipe(widget).bake!(name: 'saved').name).to eq('saved')
    expect(FactoryBakery.recipe(widget, name: 'early').bake.name).to eq('early')
    expect(FactoryBakery.recipe(widget, name: 'early').bake(name: 'late').name).to eq('late')
  end

  it 'yields the record to a block, as bake does' do
    seen = nil
    FactoryBakery.recipe(widget).bake(name: 'x') { seen = _1 }

    expect(seen.name).to eq('x')
  end

  it 'passes the keywords bake understands through' do
    expect(FactoryBakery.recipe(widget).bake(validate: false)).to be_a(widget)
    expect(FactoryBakery.recipe(widget).bake(fill_optional: true).label).to be_present
  end

  it 'is reusable: finishing a recipe leaves it as it was' do
    base = FactoryBakery.recipe(widget, :labelled, name: 'base')

    expect(base).to be_frozen
    expect(base.bake(size: 1).size).to eq(1)
    expect(base.big.bake.size).to eq(100)
    expect(base.bake.size).not_to eq(1)
    expect(base.traits).to eq([:labelled])
    expect(base.overrides).to eq(name: 'base')
  end

  it 'gives the same record as the equivalent bake call for the same seed' do
    FactoryBakery.seed = 5
    via_recipe = FactoryBakery.recipe(widget).labelled.bake(size: 7).attributes
    FactoryBakery.seed = 5
    via_bake = FactoryBakery.bake(widget, :labelled, size: 7).attributes

    expect(via_recipe).to eq(via_bake)
  ensure
    FactoryBakery.seed = nil
  end

  it 'adds a trait whose name collides with a Recipe method through trait' do
    FactoryBakery.define(widget) { trait(:trait) { label { 'collides' } } }

    expect(FactoryBakery.recipe(widget).trait(:trait).bake.label).to eq('collides')
  end

  it 'raises the usual error when a chained trait is not declared' do
    expect { FactoryBakery.recipe(widget).adimn.bake }.to raise_error(FactoryBakery::Error, /Trait :adimn/)
  end

  it 'refuses a call with arguments or a block that is not a trait' do
    recipe = FactoryBakery.recipe(widget)

    expect { recipe.labelled(1) }.to raise_error(NoMethodError)
    expect { recipe.labelled { 1 } }.to raise_error(NoMethodError)
    expect { recipe.Labelled }.to raise_error(NoMethodError)
  end

  it 'works for a registered symbol factory' do
    FactoryBakery.define(:recipe_special, klass: widget) { name { 'special' } }

    expect(FactoryBakery.recipe(:recipe_special).bake.name).to eq('special')
  end
end
