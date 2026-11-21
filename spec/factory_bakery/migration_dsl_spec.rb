# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'FactoryBakery migration DSL' do
  let(:model) { define_model('MigrationDslRecord', name: :string, label: :string, suffix: :string, skip: :string) }

  it 'rejects static attributes with the replacement syntax' do
    FactoryBakery.define(model) { name 'Ada' }

    expect { FactoryBakery.bake(model) }.to raise_error(FactoryBakery::Error, /name \{ ['"]Ada['"] \}/)
  end

  it 'rejects a false static argument even when the declaration includes a block' do
    FactoryBakery.define(model) { name(false) { 'Ada' } }

    expect { FactoryBakery.bake(model) }.to raise_error(FactoryBakery::Error, /name \{ false \}/)
  end

  it 'rejects a bare declaration and points to explicit omission' do
    FactoryBakery.define(model) { name }

    expect { FactoryBakery.bake(model) }.to raise_error(FactoryBakery::Error, /skip :name/)
  end

  it 'rejects an explicit declaration without a value block' do
    FactoryBakery.define(model) { add_attribute(:skip) }

    expect { FactoryBakery.bake(model) }.to raise_error(FactoryBakery::Error, /add_attribute\(:skip\) \{/)
  end

  it 'resolves forward and transitive reads once using the winning value' do
    calls = []
    FactoryBakery.define(model) do
      label { "#{name}-#{name}-#{suffix}" }
      name { 'base' }
      suffix { name.upcase }
      trait :renamed do
        name do
          calls << :trait
          'trait'
        end
      end
    end

    expect(FactoryBakery.bake(model).label).to eq('base-base-BASE')
    expect(FactoryBakery.bake(model, :renamed).label).to eq('trait-trait-TRAIT')
    expect(FactoryBakery.bake(model, :renamed, name: 'override').label).to eq('override-override-OVERRIDE')
    expect(calls).to eq([:trait])
  end

  it 'reads DSL-named attributes and explicit nil or false overrides' do
    FactoryBakery.define(model) do
      label { "#{skip.inspect}/#{suffix.inspect}" }
      add_attribute(:skip) { false }
      skip :suffix
    end

    expect(FactoryBakery.bake(model).label).to eq('false/nil')
    expect(FactoryBakery.bake(model, skip: nil, suffix: 'set').label).to eq('nil/"set"')
  end

  it 'names the cycle and allows breaking it with an override' do
    FactoryBakery.define(model) do
      label { name }
      name { label }
    end

    expect { FactoryBakery.bake(model) }.to raise_error(FactoryBakery::Error, /label -> name -> label/)
    expect(FactoryBakery.bake(model, name: 'Ada').label).to eq('Ada')
  end

  it 'shares generated values and honors optional filling' do
    model.validates :name, presence: true
    FactoryBakery.define(model) { label { [name, suffix].join('/') } }

    lean = FactoryBakery.bake(model)
    full = FactoryBakery.bake(model, fill_optional: [:suffix])

    expect(lean.name).to be_present
    expect(lean.label).to eq("#{lean.name}/")
    expect(lean.suffix).to be_nil
    expect(full.suffix).to be_present
    expect(full.label).to eq("#{full.name}/#{full.suffix}")
  end

  it 'resolves plugin-supplied heuristic values' do
    plugin = Object.new
    def plugin.heuristic_values(*) = { name: 'plugin' }

    FactoryBakery.register_plugin(plugin)
    FactoryBakery.define(model) { label { name.upcase } }

    expect(FactoryBakery.bake(model).label).to eq('PLUGIN')
  ensure
    FactoryBakery.unregister_plugin(plugin)
  end

  it 'resolves a heuristic with a symbol bound declared later in the factory' do
    numeric_model = define_model('DependentScore', floor: :integer, score: :integer, label: :string) do
      validates :score, numericality: { greater_than: :floor, less_than: 12_002, only_integer: true }
    end
    FactoryBakery.define(numeric_model) do
      label { "score: #{score}" }
      floor { 12_000 }
    end

    record = FactoryBakery.bake(numeric_model)

    expect(record.score).to eq(12_001)
    expect(record.label).to eq('score: 12001')
  end

  it 'names a cycle that passes through a heuristic symbol bound' do
    numeric_model = define_model('CyclicScore', floor: :integer, score: :integer) do
      validates :score, numericality: { greater_than: :floor, only_integer: true }
    end
    FactoryBakery.define(numeric_model) { floor { score } }

    expect { FactoryBakery.bake(numeric_model) }.to raise_error(FactoryBakery::Error, /floor -> score -> floor/)
  end

  it 'yields through both mixin helpers, including for a nontransactional target' do
    helpers = Object.new.extend(FactoryBakery::Methods)
    target = Class.new { attr_accessor :name }
    yielded = []
    built = helpers.bake(target, name: 'built') { |record| yielded << record }
    saved = helpers.bake!(target, name: 'saved') { |record| yielded << record }

    expect(yielded).to eq([built, saved])
    expect(yielded.map(&:name)).to eq(%w[built saved])
  end

  it 'runs the consumer once on the rebuilt record with fresh dependent values' do
    model.validates :name, presence: true, uniqueness: true, inclusion: { in: ['fixed'] }
    model.validate { errors.add(:suffix, :blank) if suffix.blank? }
    FactoryBakery.define(model) { label { "#{name}/#{suffix.to_s.upcase}" } }
    yielded = []

    record = FactoryBakery.bake(model) { |built| yielded << built }

    expect(record.suffix).to be_present
    expect(record.label).to eq("fixed/#{record.suffix.upcase}")
    expect(yielded).to eq([record])
    expect(yielded.first).to equal(record)
  end

  it 'reports a generated sibling in the explanation when validation rejects it' do
    model.validate { errors.add(:name, 'was rejected') }
    FactoryBakery.define(model) { label { name.to_s.upcase } }

    record = FactoryBakery.bake(model, fill_optional: true)

    expect(record.name).to be_present
    expect(FactoryBakery.explain(record)).to include("Chosen at random: name = #{record.name.inspect}")
  end

  it 'yields the persisted record and returns it even if the block returns something else' do
    yielded = nil
    record = FactoryBakery.bake!(model, name: 'Ada') do |created|
      expect(created).to be_persisted
      expect(model.find(created.id).name).to eq('Ada')
      yielded = created
      :ignored
    end

    expect(record).to equal(yielded)
  end

  it 'commits a bake before calling the consumer' do
    expect do
      FactoryBakery.bake!(model, name: 'Ada') { raise 'consumer failed' }
    end.to raise_error('consumer failed')

    expect(model.pluck(:name)).to eq(['Ada'])
  end

  it 'does not yield if saving fails' do
    model.validates :name, presence: true

    expect do
      FactoryBakery.bake!(model, name: nil) { raise 'yielded before saving' }
    end.to raise_error(ActiveRecord::RecordInvalid)
  end
end
