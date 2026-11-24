# frozen_string_literal: true

require 'digest'
require 'ffaker'

module FactoryBakery
  # Every random draw the gem makes goes through here. Inside a top-level bake
  # the generator is a Random derived from (seed, model class name, how many
  # top-level bakes of that class ran earlier in this process), with a stable
  # digest rather than String#hash, so one model's values do not depend on
  # which other models were baked first. Outside a bake the generator is one
  # process-wide Random derived from the seed alone. A worker id, when the
  # seed resolution found one, is hashed in as well (see Seed).
  #
  # FFaker draws from its own global generator. That generator is routed to
  # the bake's through a hook prepended to FFaker::Random's singleton class
  # (see FfakerGenerator): during a bake FFaker's helpers draw from the bake's
  # generator, so both share one stream, and FFaker's own state is never
  # touched, so nothing needs restoring.
  #
  # Threads may bake at once, so the few publications made here (a bake's
  # ordinal, the process generator, a LazyRandom's Random) happen under LOCK.
  # Each critical section is a counter bump or a nil check and assignment: no
  # user code, no derive and no seed resolution runs while LOCK is held.
  module Randomness
    STORAGE_KEY = :factory_bakery_random_scope
    LOCK = Mutex.new

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

      # Two first draws must share one Random: the nil check and the
      # assignment happen under LOCK, so a racing first draw adopts the Random
      # the other one built instead of building a second, identical one.
      def generator
        @generator || LOCK.synchronize { @generator ||= ::Random.new(seed) }
      end
    end

    # The generator of the top-level bake in flight, with the bake it belongs
    # to. `seed` is the Seed resolution the bake drew under, so provenance
    # reports the seed the values came from even if the seed changed meanwhile.
    # `active` says whether the bake is still running: `Fiber[]` storage is
    # inherited by child fibers, so a fiber created inside a bake and resumed
    # after the bake returned must not keep drawing from that bake's generator.
    Scope = Struct.new(:rng, :model, :ordinal, :seed, :active)

    # The process generator, tagged with the seed resolution it was derived
    # from, so a generator derived from a superseded seed is never reused.
    ProcessGenerator = Data.define(:resolution, :rng)

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
        resolution = Seed.current
        model = model_klass.name || model_klass.inspect
        ordinal = next_ordinal(model)
        rng = LazyRandom.new(derive(resolution, model, ordinal))
        previous = Fiber[STORAGE_KEY]
        bake_scope = Scope.new(rng:, model:, ordinal:, seed: resolution, active: true)
        Fiber[STORAGE_KEY] = bake_scope
        block.call
      ensure
        bake_scope&.active = false
        Fiber[STORAGE_KEY] = previous
      end

      # Forgets the bake counts and the process generator. Called by Seed
      # whenever the seed is re-resolved, so a new seed starts every model from
      # its first bake.
      def reset!
        LOCK.synchronize do
          @bake_counts = {}
          @process_rng = nil
        end
      end

      private

      # The read-modify-write runs under LOCK so two bakes of one model in one
      # seed generation can never read the same count.
      def next_ordinal(model)
        LOCK.synchronize do
          counts = (@bake_counts ||= {})
          ordinal = counts.fetch(model, 0)
          counts[model] = ordinal + 1
          ordinal
        end
      end

      def process_rng
        resolution = Seed.current
        published = @process_rng
        return published.rng if published&.resolution.equal?(resolution)

        publish_process_rng(resolution)
      end

      # The candidate is derived outside LOCK and published only if no
      # generator for the same resolution got there first, so every caller
      # draws from the one generator that was published.
      def publish_process_rng(resolution)
        candidate = ProcessGenerator.new(resolution:, rng: LazyRandom.new(derive(resolution, '', 0)))
        LOCK.synchronize do
          @process_rng = candidate unless @process_rng&.resolution.equal?(resolution)
          @process_rng.rng
        end
      end

      # The worker id, when the seed resolution found one, is the last part of
      # the digest input; without one the input is exactly the seed, model and
      # ordinal, so the values are the ones every earlier version produced.
      def derive(resolution, model, ordinal)
        key = "#{resolution.value}\0#{model}\0#{ordinal}"
        key = "#{key}\0#{resolution.worker}" unless resolution.worker.nil?
        Digest::SHA256.digest(key).unpack1('N')
      end
    end
  end
end
