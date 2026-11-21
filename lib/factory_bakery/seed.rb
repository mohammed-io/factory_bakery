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
  module Seed # rubocop:disable Metrics/ModuleLength
    ENV_KEY = 'FACTORY_BAKERY_SEED'
    RANDOM_LIMIT = 2**31
    LOG_FORMAT = ->(severity, _time, _program, message) { "[FactoryBakery] #{severity}: #{message}\n" }

    # origin is :env, :explicit (an Integer setting), :callable (a callable
    # setting), :framework or :random. framework is the registered integration,
    # and only set when origin is :framework.
    Resolution = Data.define(:value, :origin, :framework) do
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
        framework ? format(framework.reproduce, value) : "#{ENV_KEY}=#{value}"
      end
    end

    # A test framework's seed source. reproduce is a command template with one
    # %d for the seed; source is a callable returning the seed or nil when the
    # framework is not running.
    FrameworkSeed = Data.define(:label, :reproduce, :source)

    class << self
      attr_reader :setting, :framework
      attr_writer :logger

      # An Integer, a callable returning one, or nil to clear the setting.
      def setting=(value)
        unless valid_setting?(value)
          raise ArgumentError,
                'FactoryBakery.seed must be an Integer, a callable returning an Integer, or nil, ' \
                "got #{value.inspect}"
        end

        @setting = value
        reset!
      end

      def register_framework(label:, reproduce:, &source)
        @framework = FrameworkSeed.new(label:, reproduce:, source:)
        reset!
      end

      def logger
        defined?(@logger) ? @logger : (@logger = default_logger)
      end

      # The resolved seed. Resolution happens on the first call after a reset.
      def current
        @current ||= resolve.tap { |resolution| announce(resolution) }
      end

      def reset!
        @current = nil
        Randomness.reset!
      end

      private

      def valid_setting?(value)
        value.nil? || value.is_a?(Integer) || value.respond_to?(:call)
      end

      # The first source that answers wins; the random fallback always answers.
      def resolve
        env_resolution || setting_resolution || framework_resolution || random_resolution
      end

      def env_resolution
        value = env_seed
        Resolution.new(value:, origin: :env, framework: nil) unless value.nil?
      end

      def setting_resolution
        case setting
        when nil then nil
        when Integer then Resolution.new(value: setting, origin: :explicit, framework: nil)
        else Resolution.new(value: called_setting, origin: :callable, framework: nil)
        end
      end

      def framework_resolution
        value = framework_seed
        Resolution.new(value:, origin: :framework, framework:) unless value.nil?
      end

      def random_resolution
        Resolution.new(value: Random.new_seed % RANDOM_LIMIT, origin: :random, framework: nil)
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
