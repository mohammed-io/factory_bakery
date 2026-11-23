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
  # FFaker draws from its own global generator. That generator is routed to
  # the bake's through a hook prepended to FFaker::Random's singleton class
  # (see FfakerGenerator): during a bake FFaker's helpers draw from the bake's
  # generator, so both share one stream, and FFaker's own state is never
  # touched, so nothing needs restoring.
  module Randomness
    STORAGE_KEY = :factory_bakery_random_scope

    # A generator that builds the real `Random` on its first draw. A
    # `Random.new` costs 8-13 us (it initializes a 624-word state), and a bake
    # whose definition supplies every value draws nothing, so it pays nothing.
    # It answers the calls the gem and FFaker make: `rand`, `bytes`, and
    # `random:` for `Array#sample` / `#shuffle` (both call `rand`).
    class LazyRandom
      attr_reader :seed

      def initialize(seed)
        @seed = seed
      end

      def rand(*args)
        generator.rand(*args)
      end

      def bytes(count)
        generator.bytes(count)
      end

      private

      def generator
        @generator ||= ::Random.new(seed)
      end
    end

    # The generator of the top-level bake in flight, with the bake it belongs
    # to. `active` says whether the bake is still running: `Fiber[]` storage is
    # inherited by child fibers, so a fiber created inside a bake and resumed
    # after the bake returned must not keep drawing from that bake's generator.
    Scope = Struct.new(:rng, :model, :ordinal, :active)

    class << self
      def current
        scope&.rng || process_rng
      end

      # The top-level bake in flight, or nil outside a bake (a finished bake's
      # scope is deactivated, so fibers it spawned stop seeing it).
      def scope
        stored = Fiber[STORAGE_KEY]
        stored if stored&.active
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
        rng = LazyRandom.new(derive(seed, model, ordinal))
        previous = Fiber[STORAGE_KEY]
        bake_scope = Scope.new(rng:, model:, ordinal:, active: true)
        Fiber[STORAGE_KEY] = bake_scope
        block.call
      ensure
        bake_scope&.active = false
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
        @process_rng ||= LazyRandom.new(derive(Seed.current.value, '', 0))
      end

      def derive(seed, model, ordinal)
        Digest::SHA256.digest("#{seed}\0#{model}\0#{ordinal}").unpack1('N')
      end
    end
  end
end
