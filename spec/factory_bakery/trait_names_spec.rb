# frozen_string_literal: true

require 'spec_helper'

RSpec.describe '.trait_names' do
  let(:model) { Class.new }

  after do
    FactoryBakery::BakeryBuilder.definitions.delete(model)
    FactoryBakery::BakeryBuilder.definitions.delete(:trait_names_spec_factory)
  end

  it 'returns the declared names in definition order' do
    FactoryBakery.define(model) do
      trait(:admin) { name { 'Admin' } }
      trait(:verified) { verified { true } }
    end

    expect(FactoryBakery.trait_names(model)).to eq(%i[admin verified])
  end

  it 'returns an empty array for a definition without traits' do
    FactoryBakery.define(model) { name { 'Ada' } }

    expect(FactoryBakery.trait_names(model)).to eq([])
  end

  it 'reads a symbol factory without resolving a class' do
    FactoryBakery.define(:trait_names_spec_factory) { trait(:admin) {} }

    expect(FactoryBakery.trait_names(:trait_names_spec_factory)).to eq([:admin])
  end

  it 'reads the nearest ancestor definition for a subclass without its own, as a bake does' do
    child = Class.new(model)
    FactoryBakery.define(model) { trait(:admin) {} }

    expect(FactoryBakery.trait_names(child)).to eq([:admin])
  ensure
    FactoryBakery::BakeryBuilder.definitions.delete(child)
  end

  it 'returns an empty array when the target has no definition' do
    expect(FactoryBakery.trait_names(model)).to eq([])
    expect(FactoryBakery.trait_names(:trait_names_spec_factory)).to eq([])
  end

  it 'collects the base declarations without running values or traits or accessing the declaration cache' do
    FactoryBakery.define(model) do
      name { raise 'an attribute value ran' }
      declared_trait_names { raise 'an attribute value ran' }
      record_base_layer { raise 'an attribute value ran' }
      trait(:admin) { raise 'a trait body ran' }
    end

    expect(FactoryBakery::DeclarationCache).not_to receive(:for)
    expect(FactoryBakery.trait_names(model)).to eq([:admin])
  end
end
