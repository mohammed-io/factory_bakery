# frozen_string_literal: true

require 'logger'

module FactoryBakery
  # Decides the one seed every generated value derives from. The first source
  # that answers wins:
  #
  #   1. the FACTORY_BAKERY_SEED environment variable
  #   2. FactoryBakery.seed = value: an Integer, or a callable returning one
  #      (called lazily, when the seed is resolved)
  #   3. the test framework's seed, when an integration registered one
  #      (require 'factory_bakery/rspec' or 'factory_bakery/minitest')
  #   4. a random seed chosen once per process
  #
  # The decision is lazy: it is made on first use and memoized until a seed
  # setting changes. Each decision is announced through the logger once: INFO
  # when the test framework supplied the seed, WARN otherwise, naming the
  # source and how to reproduce the run.
  #
  # Resolution runs outside any lock (a callable and the logger are user code),
  # so two threads may resolve at once. The result is published by generation:
  # a resolution is stored only if no other one was published first and no
  # setting changed while it ran, and a racing resolver adopts the published
  # value. Each bake records the resolution it drew under, so its provenance
  # names the seed its values came from.
  #
  # Workers. A worker id is part of the derivation. The first of
  # FACTORY_BAKERY_WORKER, TEST_ENV_NUMBER (parallel_tests) or
  # PARALLEL_WORKER_NUMBER (set by the parallel test helper) that is set is read once per
  # resolution and hashed with the seed, so forked or parallel workers that
  # share a seed and a database generate different unique values. Without one
  # the values are unchanged. A failure seen in parallel worker N reproduces
  # with the worker id: the reproduce hint names FACTORY_BAKERY_WORKER=N.
  module Seed # rubocop:disable Metrics/ModuleLength
    ENV_KEY = 'FACTORY_BAKERY_SEED'
    WORKER_ENV_KEY = 'FACTORY_BAKERY_WORKER'
    WORKER_ENV_KEYS = [WORKER_ENV_KEY, 'TEST_ENV_NUMBER', 'PARALLEL_WORKER_NUMBER'].freeze
    RANDOM_LIMIT = 2**31
    LOG_FORMAT = ->(severity, _time, _program, message) { "[FactoryBakery] #{severity}: #{message}\n" }

    # origin is :env, :explicit (an Integer setting), :callable (a callable
    # setting), :framework or :random. framework is the registered integration,
    # and only set when origin is :framework. worker is the worker id in force,
    # or nil.
    Resolution = Data.define(:value, :origin, :framework, :worker) do
      def description
        case origin
        when :env then ENV_KEY
        when :explicit then 'FactoryBakery.seed='
        when :callable then 'FactoryBakery.seed= (callable)'
        when :framework then framework.label
        else 'a random choice for this process'
        end
      end

      def reproduce_hint
        command = framework ? format(framework.reproduce, value) : "#{ENV_KEY}=#{value}"
        worker.nil? ? command : "#{WORKER_ENV_KEY}=#{worker} #{command}"
      end
    end

    # A test framework's seed source. reproduce is a command template with one
    # %d for the seed; source is a callable returning the seed or nil when the
    # framework is not running.
    FrameworkSeed = Data.define(:label, :reproduce, :source)

    # A published resolution and the generation (a count of seed changes) it
    # belongs to. Immutable, so one assignment publishes it whole.
    Snapshot = Data.define(:generation, :resolution)

    PUBLISH = Mutex.new
    @generation = 0
    @snapshot = nil

    class << self # rubocop:disable Metrics/ClassLength
      attr_reader :setting, :framework
      attr_writer :logger

      # An Integer, a callable returning one, or nil to clear the setting.
      def setting=(value)
        unless valid_setting?(value)
          raise ArgumentError,
                'FactoryBakery.seed must be an Integer, a callable returning an Integer, or nil, ' \
                "got #{value.inspect}"
        end

        change { @setting = value }
      end

      def register_framework(label:, reproduce:, &source)
        change { @framework = FrameworkSeed.new(label:, reproduce:, source:) }
      end

      def logger
        defined?(@logger) ? @logger : (@logger = default_logger)
      end

      # The resolved seed. Resolution happens on the first call after a change.
      def current
        (@snapshot || publish_resolution).resolution
      end

      def reset!
        change { nil }
      end

      private

      # Every seed setting change starts a new generation and drops the published
      # resolution. The Randomness state derived from the old seed is dropped in
      # the same critical section, so nothing derived from the old seed survives it.
      def change
        PUBLISH.synchronize do
          yield
          @generation += 1
          @snapshot = nil
          Randomness.reset!
        end
      end

      def valid_setting?(value)
        value.nil? || value.is_a?(Integer) || value.respond_to?(:call)
      end

      # Resolves outside any lock, then publishes. A resolution that a setting
      # change overtook is discarded and resolved again under the new setting.
      # Only the resolver whose resolution was published announces it.
      def publish_resolution
        loop do
          generation = @generation
          resolution = resolve
          snapshot = publish(generation, resolution)
          next if snapshot.nil?

          announce(resolution) if snapshot.resolution.equal?(resolution)
          return snapshot
        end
      end

      # Publishes the resolution if none is published and the generation still
      # matches. Returns the published snapshot (ours or one already there), or
      # nil when a change overtook the resolution.
      def publish(generation, resolution)
        PUBLISH.synchronize do
          if @snapshot
            @snapshot
          elsif generation == @generation
            @snapshot = Snapshot.new(generation:, resolution:)
          end
        end
      end

      # The first source that answers wins; the random fallback always answers.
      # The worker id is read here, once per resolution.
      def resolve
        found = env_resolution || setting_resolution || framework_resolution || random_resolution
        found.with(worker: worker_id)
      end

      def env_resolution
        value = env_seed
        Resolution.new(value:, origin: :env, framework: nil, worker: nil) unless value.nil?
      end

      def setting_resolution
        case setting
        when nil then nil
        when Integer then Resolution.new(value: setting, origin: :explicit, framework: nil, worker: nil)
        else Resolution.new(value: called_setting, origin: :callable, framework: nil, worker: nil)
        end
      end

      def framework_resolution
        value = framework_seed
        Resolution.new(value:, origin: :framework, framework:, worker: nil) unless value.nil?
      end

      def random_resolution
        Resolution.new(value: Random.new_seed % RANDOM_LIMIT, origin: :random, framework: nil, worker: nil)
      end

      # The first worker variable that is set, empty included: parallel_tests
      # exports an empty TEST_ENV_NUMBER for its first worker, which is a worker
      # id of its own.
      def worker_id
        WORKER_ENV_KEYS.find { |key| ENV.key?(key) }&.then { |key| ENV.fetch(key) }
      end

      def env_seed
        raw = ENV.fetch(ENV_KEY, '').strip
        return nil if raw.empty?

        Integer(raw, 10)
      rescue ArgumentError
        raise ArgumentError, "#{ENV_KEY} must be an integer, got #{raw.inspect}"
      end

      def called_setting
        checked(setting.call, 'FactoryBakery.seed callable must return an Integer')
      end

      def framework_seed
        return nil unless framework

        value = framework.source.call
        value.nil? ? nil : checked(value, "#{framework.label} seed must be an Integer")
      end

      def checked(value, message)
        return value if value.is_a?(Integer)

        raise ArgumentError, "#{message}, got #{value.inspect}"
      end

      def announce(resolution)
        return unless logger

        logger.public_send(resolution.framework ? :info : :warn, announcement(resolution))
      end

      def announcement(resolution)
        if resolution.framework
          "using #{resolution.framework.label} seed #{resolution.value} for generated data " \
            "(#{resolution.reproduce_hint} reproduces it)"
        else
          "seed #{resolution.value} from #{resolution.description} (not the test framework's seed); " \
            "reproduce with #{resolution.reproduce_hint}"
        end
      end

      def default_logger
        Logger.new($stderr, formatter: LOG_FORMAT)
      end
    end
  end
end
