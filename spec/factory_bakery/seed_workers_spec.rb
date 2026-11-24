# frozen_string_literal: true

require 'spec_helper'
require 'logger'
require 'stringio'

# A worker id is part of the derivation: workers that share a seed and a
# database must not generate the same values. Only the environment decides the
# id, read once per seed resolution.
RSpec.describe 'seeded generation across workers' do
  include DefineConstantMacros

  let!(:model) do
    define_model('WorkerCounter', count: :integer) do
      validates :count, numericality: { only_integer: true }
    end
  end

  let(:log) { StringIO.new }
  let!(:previous_logger) { FactoryBakery.logger }

  before do
    FactoryBakery.logger = Logger.new(log, formatter: FactoryBakery::Seed::LOG_FORMAT)
  end

  after do
    FactoryBakery.seed = nil
    FactoryBakery.logger = previous_logger
  end

  # Runs the block with exactly the given worker variables set, and restores
  # the environment afterwards.
  def with_worker_env(overrides)
    variables = %w[FACTORY_BAKERY_SEED FACTORY_BAKERY_WORKER TEST_ENV_NUMBER PARALLEL_WORKER_NUMBER]
    saved = variables.to_h { |key| [key, ENV.fetch(key, nil)] }
    variables.each { |key| ENV.delete(key) }
    overrides.each { |key, value| ENV[key] = value }
    yield
  ensure
    saved&.each { |key, value| value.nil? ? ENV.delete(key) : ENV[key] = value }
  end

  # The values five bakes draw under seed 42 in the current environment. The
  # seed is resolved inside the block, so the environment it sees is the one set.
  def values_for_forty_two_seed
    FactoryBakery.seed = 42
    Array.new(5) { FactoryBakery.bake(model).count }
  end

  it 'gives workers that share a seed different values' do
    worker_one = with_worker_env('FACTORY_BAKERY_WORKER' => '1') { values_for_forty_two_seed }
    worker_two = with_worker_env('FACTORY_BAKERY_WORKER' => '2') { values_for_forty_two_seed }

    expect(worker_two).not_to eq(worker_one)
  end

  it 'gives the same values for the same worker id, every run' do
    first = with_worker_env('FACTORY_BAKERY_WORKER' => '2') { values_for_forty_two_seed }
    second = with_worker_env('FACTORY_BAKERY_WORKER' => '2') { values_for_forty_two_seed }

    expect(second).to eq(first)
  end

  it 'reads a parallel_tests worker number as the worker id' do
    from_parallel_tests = with_worker_env('TEST_ENV_NUMBER' => '2') { values_for_forty_two_seed }
    from_factory_bakery = with_worker_env('FACTORY_BAKERY_WORKER' => '2') { values_for_forty_two_seed }

    expect(from_parallel_tests).to eq(from_factory_bakery)
  end

  it 'treats an empty TEST_ENV_NUMBER as the first parallel_tests worker, not as no worker' do
    first_worker = with_worker_env('TEST_ENV_NUMBER' => '') { values_for_forty_two_seed }
    unparallelised = with_worker_env({}) { values_for_forty_two_seed }

    expect(first_worker).not_to eq(unparallelised)
  end

  it 'prefers FACTORY_BAKERY_WORKER, then TEST_ENV_NUMBER, then PARALLEL_WORKER_NUMBER' do
    by_factory_bakery = with_worker_env('FACTORY_BAKERY_WORKER' => '7') { values_for_forty_two_seed }
    all_set = with_worker_env(
      'FACTORY_BAKERY_WORKER' => '7', 'TEST_ENV_NUMBER' => '2', 'PARALLEL_WORKER_NUMBER' => '3'
    ) { values_for_forty_two_seed }
    parallel_tests_over_rails = with_worker_env('TEST_ENV_NUMBER' => '2', 'PARALLEL_WORKER_NUMBER' => '3') do
      values_for_forty_two_seed
    end
    by_parallel_tests = with_worker_env('FACTORY_BAKERY_WORKER' => '2') { values_for_forty_two_seed }

    expect(all_set).to eq(by_factory_bakery)
    expect(parallel_tests_over_rails).to eq(by_parallel_tests)
  end

  it 'names the worker in the reproduce hint, so a failure from worker N reproduces with it' do
    with_worker_env('FACTORY_BAKERY_WORKER' => '2') { values_for_forty_two_seed }

    expect(log.string).to include('reproduce with FACTORY_BAKERY_WORKER=2 FACTORY_BAKERY_SEED=42')
  end
end
