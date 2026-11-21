# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'explaining a record a random value made invalid' do
  # An app rule the gem cannot see: only one provider is accepted, so a random
  # word is always rejected. The rule is a custom validation, not a constraint.
  let!(:llm) do
    define_model('SeedLlm', provider: :string, region: :string) do
      validate { errors.add(:provider, 'is not supported by this app') unless provider == 'open_ai' }
    end
  end

  let!(:based) do
    define_model('SeedBased', provider: :string) do
      validate { errors.add(:base, 'Provider is not supported by this app') unless provider == 'open_ai' }
    end
  end

  def pinned_snippet(klass, attribute, value)
    ["FactoryBakery.define(#{klass}) do", "  #{attribute} { nil } # was randomly #{value.inspect}; " \
     'use a value your validations accept', 'end']
  end

  around do |example|
    previous_paths = FactoryBakery.definition_paths
    example.run
  ensure
    FactoryBakery.definition_paths = previous_paths
  end

  before do
    FactoryBakery.definition_paths = ['spec/factories']
    FactoryBakery.seed = 1234
  end

  after do
    FactoryBakery.register_test_framework_seed(label: 'Fake', reproduce: 'fake --seed %d') { nil }
    FactoryBakery.seed = nil
  end

  describe 'FactoryBakery.explain for a plain bake' do
    it 'names the invalid attribute, the value chosen at random, the seed and a pinning snippet' do
      record = FactoryBakery.bake(llm)
      text = FactoryBakery.explain(record)
      chosen = record.provider.inspect

      expect(text).to include('FactoryBakery could not produce a valid SeedLlm. Invalid attributes:')
      expect(text).to include('  - provider: is not supported by this app')
      expect(text).to include("Chosen at random: provider = #{chosen}")
      expect(text).to include('Seed 1234 from FactoryBakery.seed=. Reproduce: FACTORY_BAKERY_SEED=1234')
      expect(text).to include(*pinned_snippet('SeedLlm', 'provider', record.provider))
    end

    it 'gives the agent instruction with the file path, the errors and the reproduce command' do
      text = FactoryBakery.explain(FactoryBakery.bake(llm))

      expect(text).to include(
        'Agent: edit spec/factories/seed_llm.rb, add the block above inside FactoryBakery.define(SeedLlm), ' \
        'choose values that satisfy provider is not supported by this app, ' \
        'then re-run with FACTORY_BAKERY_SEED=1234'
      )
    end

    it 'does not list attributes that no random value is behind' do
      text = FactoryBakery.explain(FactoryBakery.bake(llm))

      expect(text).not_to include('Chosen at random: region')
      expect(text).not_to include('region {')
    end

    it 'says "your definitions file" when no definition path is configured' do
      FactoryBakery.definition_paths = []

      text = FactoryBakery.explain(FactoryBakery.bake(llm))

      expect(text).to include('pin it in your definitions file:')
      expect(text).to include('Agent: edit your definitions file, add the block above')
    end

    it 'names a base error\'s attribute when the message mentions it' do
      text = FactoryBakery.explain(FactoryBakery.bake(based))

      expect(text).to include('  - base: Provider is not supported by this app')
      expect(text).to match(/Chosen at random: provider = .* \(named in a base error\)/)
    end

    it 'reproduces with the framework command when the test framework supplied the seed' do
      FactoryBakery.seed = nil
      FactoryBakery.register_test_framework_seed(label: 'Fake', reproduce: 'fake --seed %d') { 4242 }

      text = FactoryBakery.explain(FactoryBakery.bake(llm))

      expect(text).to include('Seed 4242 from Fake. Reproduce: fake --seed 4242')
      expect(text).to include('then re-run with fake --seed 4242')
      expect(text).not_to include('FACTORY_BAKERY_SEED')
    end

    it 'reports a valid record as having nothing to explain' do
      valid = define_model('SeedValid', code: :string)

      expect(FactoryBakery.explain(FactoryBakery.bake(valid))).to eq('SeedValid is valid; nothing to explain.')
    end

    it 'says so for a record that FactoryBakery did not build' do
      record = llm.new(provider: 'bedrock')

      expect(FactoryBakery.explain(record)).to include(
        'This record was not built by FactoryBakery; no value came from it at random.'
      )
    end
  end

  describe 'bake!' do
    it 'keeps the exception class and the original message first, then the explanation' do
      expected = begin
        FactoryBakery.seed = 1234
        FactoryBakery.bake(llm).provider
      end

      FactoryBakery.seed = 1234
      expect { FactoryBakery.bake!(llm) }.to raise_error(ActiveRecord::RecordInvalid) do |error|
        expect(error.message.lines.first).to start_with('Validation failed: Provider is not supported by this app')
        expect(error.message).to include("Chosen at random: provider = #{expected.inspect}")
        expect(error.message).to include('Seed 1234 from FactoryBakery.seed=. Reproduce: FACTORY_BAKERY_SEED=1234')
        expect(error.record).to be_a(llm)
      end
    end
  end
end
