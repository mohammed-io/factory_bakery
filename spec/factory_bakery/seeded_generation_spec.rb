# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'seeded generation' do
  let!(:widget) do
    define_model('SeedWidget', name: :string, count: :integer) do
      validates :name, presence: true
      validates :count, numericality: { only_integer: true }
    end
  end

  let!(:gadget) do
    define_model('SeedGadget', label: :string) do
      validates :label, presence: true
    end
  end

  def widget_values(klass = widget)
    record = FactoryBakery.bake(klass)
    [record.name, record.count]
  end

  after { FactoryBakery.seed = nil }

  it 'gives the same values for the same seed across runs' do
    FactoryBakery.seed = 42
    first_run = [widget_values, widget_values]

    FactoryBakery.seed = 42
    second_run = [widget_values, widget_values]

    expect(second_run).to eq(first_run)
  end

  it 'gives different values for a different seed' do
    FactoryBakery.seed = 42
    with_forty_two = widget_values

    FactoryBakery.seed = 43

    expect(widget_values).not_to eq(with_forty_two)
  end

  it 'gives a model the same values whichever other models were baked before it' do
    FactoryBakery.seed = 42
    alone = widget_values

    FactoryBakery.seed = 42
    FactoryBakery.bake(gadget)
    FactoryBakery.bake(gadget)
    after_others = widget_values

    expect(after_others).to eq(alone)
  end

  it 'gives a later bake of the same model its own values, reproducibly' do
    FactoryBakery.seed = 42
    later = [widget_values, widget_values].last

    FactoryBakery.seed = 42
    expect([widget_values, widget_values].last).to eq(later)
    expect(widget_values).not_to eq(later)
  end

  it 'does not build a random generator when the definition supplies every value' do
    FactoryBakery.seed = 7
    FactoryBakery.define(widget) do
      name { 'fixed' }
      count { 3 }
    end

    expect(Random).not_to receive(:new)

    expect(FactoryBakery.bake(widget).attributes.values_at('name', 'count')).to eq(['fixed', 3])
  end

  it 'builds one random generator shared by generated values and FFaker' do
    FactoryBakery.seed = 7
    FactoryBakery.define(widget) do
      name { FFaker::Name.name }
    end

    expect(Random).to receive(:new).once.and_call_original

    expect(FactoryBakery.bake(widget).count).to be_a(Integer)
  end

  describe 'FFaker' do
    let!(:named) do
      define_model('SeedNamed', full_name: :string) do
        validates :full_name, presence: true
      end
    end

    before do
      FactoryBakery.define(named) do
        full_name { FFaker::Name.name }
      end
    end

    def full_name_for(seed)
      FactoryBakery.seed = seed
      FactoryBakery.bake(named).full_name
    end

    it 'draws the same FFaker values for the same seed' do
      expect(full_name_for(7)).to eq(full_name_for(7))
    end

    it 'draws different FFaker values for a different seed' do
      expect(full_name_for(7)).not_to eq(full_name_for(8))
    end

    it 'leaves FFaker\'s own seed alone once the bake returns' do
      FactoryBakery.seed = 7
      previous = FFaker::Random.seed

      FactoryBakery.bake(named)

      expect(FFaker::Random.seed).to eq(previous)
    end

    it 'leaves FFaker\'s own value stream where it was, as if the bake never drew from it' do
      FFaker::Random.seed = 1234
      expected = Array.new(3) { FFaker::Name.name }

      FFaker::Random.seed = 1234
      FactoryBakery.seed = 7
      FactoryBakery.bake(named)

      expect(Array.new(3) { FFaker::Name.name }).to eq(expected)
    end

    it 'leaves FFaker\'s own seed alone even when the bake raises' do
      FFaker::Random.seed = 99
      before_seed = FFaker::Random.seed
      FactoryBakery.define(named) { full_name { raise 'boom' } }

      expect { FactoryBakery.bake(named) }.to raise_error(/boom/)
      expect(FFaker::Random.seed).to eq(before_seed)
    end

    it 'draws from its own generator outside a bake' do
      FFaker::Random.seed = 5
      first = FFaker::Name.name

      FFaker::Random.seed = 5

      expect(FFaker::Name.name).to eq(first)
    end
  end

  describe 'overlapping bakes' do
    let!(:alpha) do
      define_model('SeedParallelAlpha', full_name: :string) { validates :full_name, presence: true }
    end

    let!(:beta) do
      define_model('SeedParallelBeta', full_name: :string) { validates :full_name, presence: true }
    end

    def faker_bake(klass, suspend: false)
      FactoryBakery::Randomness.top_level_bake(klass) do
        Fiber.yield if suspend
        FFaker::Name.name
      end
    end

    # Each solo bake starts from a fresh seed, so its bake count for the model
    # is zero and the generator derives from (seed, model, 0) exactly as an
    # overlapping bake of the same class does.
    def solo_values
      [alpha, beta].map do |klass|
        FactoryBakery.seed = 11
        faker_bake(klass)
      end
    end

    it 'gives two overlapping fibers the values their bakes get when run alone' do
      solo = solo_values

      FactoryBakery.seed = 11
      fibers = [alpha, beta].map { |klass| Fiber.new { faker_bake(klass, suspend: true) } }
      fibers.each(&:resume)
      values = fibers.map(&:resume)

      expect(values).to eq(solo)
    end

    it 'stops a fiber created inside a finished bake from drawing with that bake\'s generator' do
      inside = nil
      fiber = nil
      FactoryBakery.seed = 11
      FactoryBakery::Randomness.top_level_bake(alpha) do
        inside = FFaker::Random.rng
        fiber = Fiber.new do
          Fiber.yield
          FFaker::Random.rng
        end
        fiber.resume
      end

      after = fiber.resume

      expect(after).not_to equal(inside)
    end

    it 'gives two threads baking different classes the values their bakes get when run alone' do
      solo = solo_values

      FactoryBakery.seed = 11
      values = [alpha, beta].map { |klass| Thread.new { faker_bake(klass) } }.map(&:value)

      expect(values).to eq(solo)
    end
  end
end
