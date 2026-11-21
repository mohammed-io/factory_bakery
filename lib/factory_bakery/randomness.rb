# frozen_string_literal: true

require 'digest'
require 'ffaker'

module FactoryBakery
  # Every random draw the gem makes goes through here. Inside a top-level bake
  # the generator is a Random derived from (seed, model class name, how many
  # top-level bakes of that class ran earlier in this process), with a stable
  # digest rather than String#hash, so one model's values do not depend on
  # which other models were baked first. Outside a bake the generator is one
  # process-wide Random derived from the seed alone.
  #
  # FFaker draws from its own global generator. For the duration of a
  # top-level bake that generator is seeded from the bake's Random, and its
  # previous seed is restored afterwards.
  module Randomness
    STORAGE_KEY = :factory_bakery_random_scope
    FFAKER_SEED_LIMIT = 2**62

    # The generator of the top-level bake in flight, with the bake it belongs to.
    Scope = Data.define(:rng, :model, :ordinal)

    class << self
      def current
        scope = Fiber[STORAGE_KEY]
        scope ? scope.rng : process_rng
      end

      # The top-level bake in flight, or nil outside a bake.
      def scope
        Fiber[STORAGE_KEY]
      end

      def rand(*args)
        current.rand(*args)
      end

      def sample(collection, *count)
        collection.sample(*count, random: current)
      end

      def hex(bytes)
        current.bytes(bytes).unpack1('H*')
      end

      def top_level_bake(model_klass, &block)
        seed = Seed.current.value
        model = model_klass.name || model_klass.inspect
        ordinal = next_ordinal(model)
        rng = Random.new(derive(seed, model, ordinal))
        previous = Fiber[STORAGE_KEY]
        Fiber[STORAGE_KEY] = Scope.new(rng:, model:, ordinal:)
        with_faker_seed(rng.rand(FFAKER_SEED_LIMIT), &block)
      ensure
        Fiber[STORAGE_KEY] = previous
      end

      # Forgets the bake counts and the process generator. Called whenever the
      # seed is re-resolved, so a new seed starts every model from its first bake.
      def reset!
        @bake_counts = {}
        @process_rng = nil
      end

      private

      def next_ordinal(model)
        counts = (@bake_counts ||= {})
        ordinal = counts.fetch(model, 0)
        counts[model] = ordinal + 1
        ordinal
      end

      def process_rng
        @process_rng ||= Random.new(derive(Seed.current.value, '', 0))
      end

      def derive(seed, model, ordinal)
        Digest::SHA256.digest("#{seed}\0#{model}\0#{ordinal}").unpack1('Q>')
      end

      def with_faker_seed(seed)
        previous = FFaker::Random.seed
        FFaker::Random.seed = seed
        yield
      ensure
        FFaker::Random.seed = previous
      end
    end
  end
end
