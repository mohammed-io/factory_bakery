# frozen_string_literal: true

require 'spec_helper'
require 'logger'
require 'stringio'

# The seed is published once per generation. A resolution that a racing
# resolver or a setting change overtakes must not overwrite the seed in force,
# is announced only when it is the one published, and a bake reports the seed
# it drew under.
RSpec.describe 'seed publication' do
  include DefineConstantMacros

  let(:log) { StringIO.new }
  let!(:previous_logger) { FactoryBakery.logger }

  before do
    FactoryBakery.logger = Logger.new(log, formatter: FactoryBakery::Seed::LOG_FORMAT)
  end

  after do
    FactoryBakery.seed = nil
    FactoryBakery.logger = previous_logger
  end

  it 'keeps the seed a racing resolver published while the first resolver was inside the callable' do
    first = true
    FactoryBakery.seed = lambda do
      if first
        first = false
        Fiber.yield(:resolving)
        100
      else
        200
      end
    end
    resolver = Fiber.new { FactoryBakery.seed }

    expect(resolver.resume).to eq(:resolving)
    expect(FactoryBakery.seed).to eq(200)
    expect(resolver.resume).to eq(200)
    expect(FactoryBakery.seed).to eq(200)
  end

  it 'keeps a setting made while the resolver was inside the callable' do
    FactoryBakery.seed = lambda do
      Fiber.yield(:resolving)
      300
    end
    resolver = Fiber.new { FactoryBakery.seed }
    expect(resolver.resume).to eq(:resolving)

    FactoryBakery.seed = 400
    expect(FactoryBakery.seed).to eq(400)

    resolver.resume
    expect(FactoryBakery.seed).to eq(400)
  end

  it 'announces one resolution once, even when a racing resolver finishes after it' do
    first = true
    FactoryBakery.seed = lambda do
      if first
        first = false
        Fiber.yield(:resolving)
        100
      else
        200
      end
    end
    resolver = Fiber.new { FactoryBakery.seed }
    resolver.resume
    FactoryBakery.seed
    resolver.resume

    expect(log.string.lines.size).to eq(1)
    expect(log.string).to include('seed 200 from FactoryBakery.seed= (callable)')
  end

  it 'reports the seed a bake drew under, not the seed set while it was in flight' do
    klass = Class.new { attr_accessor :sample }
    FactoryBakery.seed = 500
    FactoryBakery.define(klass) do
      sample do
        draw = FactoryBakery::Randomness.rand(2**30)
        Fiber.yield(draw)
        draw
      end
    end
    bake = Fiber.new { FactoryBakery.bake(klass) }
    bake.resume

    FactoryBakery.seed = 600
    record = bake.resume

    expect(FactoryBakery::Provenance.of(record).seed.value).to eq(500)
  end
end
