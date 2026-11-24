# frozen_string_literal: true

require 'spec_helper'
require 'timeout'

# Concurrent bakes draw from one seed generation: each bake takes its own
# ordinal, and the first draws outside a bake come from one published generator.
RSpec.describe 'randomness under concurrent use' do
  include DefineConstantMacros

  let!(:model) { define_model('RandomnessRacer', count: :integer) }

  after { FactoryBakery.seed = nil }

  # A count table whose first read parks its reader until the test releases it,
  # so the other bakes read the table while the parked bake is mid-update.
  def parking_counts(entered, proceed)
    Class.new(Hash) do
      define_method(:fetch) do |key, *default|
        value = super(key, *default)
        if Thread.current[:factory_bakery_parked]
          Thread.current[:factory_bakery_parked] = false
          entered << :parked
          proceed.pop
        end
        value
      end
    end.new
  end

  def ordinal_of_a_bake
    FactoryBakery::Randomness.top_level_bake(model) { FactoryBakery::Randomness.scope.ordinal }
  end

  # Returns once the thread is parked on the lock or has finished.
  def wait_until_settled(thread)
    Timeout.timeout(5) { Thread.pass until thread.stop? || !thread.alive? }
  end

  it 'gives N threads baking one model in one seed generation N distinct ordinals' do
    FactoryBakery.seed = 3
    entered = Queue.new
    proceed = Queue.new
    FactoryBakery::Randomness.instance_variable_set(:@bake_counts, parking_counts(entered, proceed))

    parked = Thread.new do
      Thread.current[:factory_bakery_parked] = true
      ordinal_of_a_bake
    end
    entered.pop
    others = Array.new(2) { Thread.new { ordinal_of_a_bake } }
    others.each { |thread| wait_until_settled(thread) }
    proceed << :go

    expect([parked.value, *others.map(&:value)]).to contain_exactly(0, 1, 2)
  end

  it 'draws the first values outside a bake from one published generator under concurrent first use' do
    FactoryBakery.seed = 9
    solo = [FactoryBakery::Randomness.rand(1_000_000), FactoryBakery::Randomness.rand(1_000_000)]

    FactoryBakery.seed = 9
    gate = Mutex.new
    rendezvous = ConditionVariable.new
    arrived = 0
    allow(FactoryBakery::Randomness).to receive(:derive).and_wrap_original do |original, *args|
      gate.synchronize do
        arrived += 1
        rendezvous.broadcast
        rendezvous.wait(gate, 2) if arrived < 2
      end
      original.call(*args)
    end

    values = Array.new(2) { Thread.new { FactoryBakery::Randomness.rand(1_000_000) } }.map(&:value)

    expect(values.sort).to eq(solo.sort)
  end
end
