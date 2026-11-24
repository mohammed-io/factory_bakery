# frozen_string_literal: true

require 'spec_helper'

# The name-list snapshot a build reads instead of re-deriving its lists.
# Observable outputs only: the derived lists, their frozenness, and the
# normalized hashes.
RSpec.describe FactoryBakery::BakeryBuilder::Names do
  let(:declaration_stream) do
    [
      [:name, -> { 'x' }],
      ['age'.to_sym, -> { 1 }]
    ]
  end

  let(:plugin_entry) { Struct.new(:name).new(:account) }
  let(:plugin_declarations) { { plugin_object: [plugin_entry, :tagged] } }

  subject(:names) do
    described_class.new(
      declared: FactoryBakery::DeclarationSet.new(declaration_stream).names,
      plugin_declarations: plugin_declarations,
      overrides: overrides,
      initialize_with: initialize_with
    )
  end

  context 'with overrides and initialize_with attributes' do
    let(:overrides) { { name: 'override', email: 'a@b.c' } }
    let(:initialize_with) { { 'role' => 'admin' } }

    it 'derives the declared names as strings' do
      expect(names.declared).to eq(%w[name age])
    end

    it 'derives the plugin declared names from entry names and bare entries' do
      expect(names.plugin_declared).to eq(%w[account tagged])
    end

    it 'normalizes the override keys to strings' do
      expect(names.override_keys).to eq(%w[name email])
      expect(names.overrides).to eq('name' => 'override', 'email' => 'a@b.c')
    end

    it 'normalizes the initialize_with keys to strings' do
      expect(names.init_with_keys).to eq(['role'])
      expect(names.initialize_with).to eq('role' => 'admin')
    end

    it 'derives the taken names from every layer' do
      expect(names.raw_taken).to eq(%w[name age account tagged name email role])
    end

    it 'derives the explicit names from declarations and overrides' do
      expect(names.explicit).to eq(%w[name age name email])
    end

    it 'derives the suppression seeds from declarations, overrides and initialize_with' do
      expect(names.suppression_seeds).to eq(%w[name age name email role])
    end

    it 'freezes every list it hands out' do
      expect(names.declared).to be_frozen
      expect(names.plugin_declared).to be_frozen
      expect(names.override_keys).to be_frozen
      expect(names.init_with_keys).to be_frozen
      expect(names.raw_taken).to be_frozen
      expect(names.explicit).to be_frozen
      expect(names.suppression_seeds).to be_frozen
      expect(names.overrides).to be_frozen
      expect(names.initialize_with).to be_frozen
    end
  end

  context 'with nil overrides and initialize_with' do
    let(:overrides) { nil }
    let(:initialize_with) { nil }

    it 'returns empty frozen lists' do
      expect(names.override_keys).to eql([])
      expect(names.init_with_keys).to eql([])
      expect(names.override_keys).to be_frozen
      expect(names.init_with_keys).to be_frozen
      expect(names.overrides).to eql({})
      expect(names.initialize_with).to eql({})
      expect(names.overrides).to be_frozen
      expect(names.initialize_with).to be_frozen
    end
  end

  context 'with empty overrides and initialize_with' do
    let(:overrides) { {} }
    let(:initialize_with) { {} }

    it 'returns empty frozen lists' do
      expect(names.override_keys).to eql([])
      expect(names.init_with_keys).to eql([])
      expect(names.overrides).to eql({})
      expect(names.initialize_with).to eql({})
      expect(names.overrides).to be_frozen
      expect(names.initialize_with).to be_frozen
    end
  end

  context 'with no plugin declarations' do
    let(:plugin_declarations) { nil }
    let(:overrides) { nil }
    let(:initialize_with) { nil }

    it 'derives an empty frozen plugin list' do
      expect(names.plugin_declared).to eql([])
      expect(names.plugin_declared).to be_frozen
      expect(names.raw_taken).to eq(%w[name age])
    end
  end

  context 'with a live plugin-declaration bucket' do
    let(:overrides) { nil }
    let(:initialize_with) { nil }
    let(:plugin_declarations) { Hash.new { |hash, plugin| hash[plugin] = [] } }

    it 'reads plugin-declared names live, so a declaration recorded after the build started is seen' do
      expect(names.plugin_declared).to eql([])

      plugin_declarations[:plugin_object] << Struct.new(:name).new(:late)

      expect(names.plugin_declared).to eq(%w[late])
      expect(names.plugin_declared).to be_frozen
      expect(names.raw_taken).to include('late')
      expect(names.raw_taken).to be_frozen
    end
  end
end
