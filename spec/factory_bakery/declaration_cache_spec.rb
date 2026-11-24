# frozen_string_literal: true

require 'spec_helper'

# A definition's declarations are recorded once and reused (ADR-0009). The
# observable contract: the declaration block runs once for a static
# definition, values stay dynamic, call-site overrides and traits behave as
# before, and anything that cannot be reused is evaluated on every bake.
RSpec.describe 'declaration cache' do
  let!(:widget) do
    define_model('CachedWidget', name: :string, label: :string, size: :integer) do
      validates :name, presence: true
    end
  end

  let(:runs) { { definition: 0, trait: 0 } }

  def define_counted(runs)
    FactoryBakery.define(widget) do
      runs[:definition] += 1
      name { 'declared' }
      size { rand(1..1_000_000) }

      trait :labelled do
        runs[:trait] += 1
        label { 'tagged' }
      end

      trait :renamed do
        name { 'renamed' }
      end
    end
  end

  before { define_counted(runs) }

  it 'runs the definition block once however many times it bakes' do
    Array.new(3) { FactoryBakery.bake(widget) }

    expect(runs[:definition]).to eq(1)
  end

  it 'still calls each value block on every bake' do
    sizes = Array.new(5) { FactoryBakery.bake(widget).size }

    expect(sizes.uniq.size).to be > 1
  end

  it 'applies call-site overrides over the cached declarations' do
    FactoryBakery.bake(widget)

    expect(FactoryBakery.bake(widget, name: 'override').name).to eq('override')
    expect(FactoryBakery.bake(widget).name).to eq('declared')
  end

  it 'runs a trait block once and applies it every time it is requested' do
    records = Array.new(3) { FactoryBakery.bake(widget, :labelled) }

    expect(records.map(&:label)).to all(eq('tagged'))
    expect(runs[:trait]).to eq(1)
  end

  it 'keeps trait order: a later trait beats the base and an earlier trait' do
    expect(FactoryBakery.bake(widget, :labelled, :renamed).name).to eq('renamed')
    expect(FactoryBakery.bake(widget, :renamed, :labelled).label).to eq('tagged')
    expect(FactoryBakery.bake(widget, :renamed, :labelled).name).to eq('renamed')
  end

  it 'gives a bake without the trait no trait declarations after a bake with it' do
    FactoryBakery.bake(widget, :labelled)

    expect(FactoryBakery.bake(widget).label).not_to eq('tagged')
  end

  it 'still rejects an undeclared trait once the base is cached' do
    FactoryBakery.bake(widget)

    expect { FactoryBakery.bake(widget, :missing) }.to raise_error(FactoryBakery::Error, /Trait :missing/)
  end

  it 'evaluates the new block after the target is defined again' do
    FactoryBakery.bake(widget)
    FactoryBakery.define(widget) { name { 'second' } }

    expect(FactoryBakery.bake(widget).name).to eq('second')
  end

  it 'caches nothing from a block that raised, so a later success is recorded' do
    attempts = 0
    FactoryBakery.define(widget) do
      attempts += 1
      raise 'boom' if attempts == 1

      name { 'recovered' }
    end

    expect { FactoryBakery.bake(widget) }.to raise_error(/boom/)
    expect(FactoryBakery.bake(widget).name).to eq('recovered')
    FactoryBakery.bake(widget)
    expect(attempts).to eq(2)
  end

  it 'does not reuse a definition that calls initialize_with: it runs on every bake' do
    count = 0
    FactoryBakery.define(widget) do
      count += 1
      initialize_with(name: "built-#{count}")
    end

    names = Array.new(2) { FactoryBakery.bake(widget).name }

    expect(names).to eq(%w[built-1 built-2])
  end

  it 'does not reuse a trait that calls initialize_with, but still reuses the base' do
    base_runs = 0
    trait_runs = 0
    FactoryBakery.define(widget) do
      base_runs += 1
      name { 'declared' }
      trait(:built) do
        trait_runs += 1
        initialize_with(name: "built-#{trait_runs}")
      end
    end

    Array.new(2) { FactoryBakery.bake(widget, :built) }

    expect([base_runs, trait_runs]).to eq([1, 2])
  end

  it 'evaluates a definition whose block has been frozen on every bake' do
    count = 0
    block = proc do
      count += 1
      name { 'frozen' }
    end
    FactoryBakery.define(widget, &block.freeze)

    Array.new(2) { FactoryBakery.bake(widget) }

    expect(count).to eq(2)
  end

  it 'works for a class baked with no definition at all' do
    bare = define_model('CachedBare', name: :string) { validates :name, presence: true }

    expect(Array.new(2) { FactoryBakery.bake(bare).name }).to all(be_present)
  end

  it 'caches per named factory independently of the class' do
    named_runs = 0
    FactoryBakery.define(:cached_special, klass: widget) do
      named_runs += 1
      name { 'special' }
    end

    records = Array.new(2) { FactoryBakery.bake(:cached_special) }

    expect(records.map(&:name)).to all(eq('special'))
    expect(named_runs).to eq(1)
  end
end
