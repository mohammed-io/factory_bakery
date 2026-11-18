# frozen_string_literal: true

module FactoryBakery
  # Opt-in association building. Configuration lives with the plugin so core
  # stays ignorant of it.
  module Associations
    MODES = %i[none required_only all].freeze
    STRATEGIES = %i[fresh reuse].freeze
    DEFAULT_MODE = :required_only
    DEFAULT_STRATEGY = :fresh
    DEFAULT_MAX_DEPTH = 2
    DEFAULT_COUNT = 1

    # Scoped overrides are fiber-local (like core's build context): sibling
    # threads and fibers never see each other's scope, and a value is replaced
    # rather than mutated so a child fiber cannot change its parent's scope.
    SCOPE_KEY = :factory_bakery_associations_scope
    SCOPE_KEYS = %i[mode strategy max_depth default_count].freeze
    EMPTY_SCOPE = {}.freeze

    class << self
      # Readers report the effective value: the scoped override when one is
      # active, otherwise the process-wide global value.
      def mode
        scope.fetch(:mode) { global_mode }
      end

      def mode=(value)
        @global_mode = validated_mode!(value)
      end

      # The strategy for edges that do not name one themselves. Per-association
      # `strategy:` still wins, then this scoped/global value.
      def strategy
        scope.fetch(:strategy) { global_strategy }
      end

      def strategy=(value)
        @global_strategy = validated_strategy!(value)
      end

      # Association hops allowed from the root of one bake. Past this budget
      # :all keeps building only required belongs_to edges so objects stay
      # valid; it never raises for depth alone.
      def max_depth
        scope.fetch(:max_depth) { global_max_depth }
      end

      def max_depth=(value)
        @global_max_depth = non_negative_integer!(value, :max_depth)
      end

      # Children built per has_many in :all. has_one always builds one.
      def default_count
        scope.fetch(:default_count) { global_default_count }
      end

      def default_count=(value)
        @global_default_count = non_negative_integer!(value, :default_count)
      end

      # Runs the block with temporary configuration overrides. The scope covers
      # the whole nested graph (including bakes made from declaration blocks),
      # nests with an inner scope winning, and is restored in `ensure` even if
      # the block raises. Returns the block's value.
      #
      # A block is used instead of a `bake` keyword because **overrides shares
      # its namespace with model attributes: an `associations:` kwarg could
      # collide with a real column.
      def with(**overrides)
        previous = scope
        validate_scope!(overrides)
        Fiber[SCOPE_KEY] = previous.merge(overrides).freeze
        yield
      ensure
        Fiber[SCOPE_KEY] = previous
      end

      # Test support: resets global config to its defaults and clears this
      # fiber's scope so examples never leak configuration into each other.
      def reset_configuration!
        @global_mode = DEFAULT_MODE
        @global_strategy = DEFAULT_STRATEGY
        @global_max_depth = DEFAULT_MAX_DEPTH
        @global_default_count = DEFAULT_COUNT
        Fiber[SCOPE_KEY] = EMPTY_SCOPE
      end

      # The build context counts nested public bakes: the root is depth 1, so
      # its direct association targets are depth 2.
      def past_depth?(context)
        !context.nil? && context.depth > max_depth
      end

      # Exposed so the `association` DSL can reject a bad strategy as soon as
      # its declaration is evaluated.
      def validated_strategy!(value)
        return value if STRATEGIES.include?(value)

        raise ArgumentError, "invalid associations strategy #{value.inspect}; expected one of #{STRATEGIES.inspect}"
      end

      private

      def scope
        Fiber[SCOPE_KEY] || EMPTY_SCOPE
      end

      def global_mode
        @global_mode ||= DEFAULT_MODE
      end

      def global_strategy
        @global_strategy ||= DEFAULT_STRATEGY
      end

      def global_max_depth
        @global_max_depth ||= DEFAULT_MAX_DEPTH
      end

      def global_default_count
        @global_default_count ||= DEFAULT_COUNT
      end

      def validate_scope!(overrides)
        overrides.each_key do |key|
          next if SCOPE_KEYS.include?(key)

          raise ArgumentError,
                "unknown associations scope option #{key.inspect}; expected one of #{SCOPE_KEYS.inspect}"
        end

        validate_scope_values!(overrides)
      end

      def validate_scope_values!(overrides)
        validated_mode!(overrides[:mode]) if overrides.key?(:mode)
        validated_strategy!(overrides[:strategy]) if overrides.key?(:strategy)
        non_negative_integer!(overrides[:max_depth], :max_depth) if overrides.key?(:max_depth)
        non_negative_integer!(overrides[:default_count], :default_count) if overrides.key?(:default_count)
      end

      def validated_mode!(value)
        return value if MODES.include?(value)

        raise ArgumentError, "invalid associations mode #{value.inspect}; expected one of #{MODES.inspect}"
      end

      def non_negative_integer!(value, name)
        return value if value.is_a?(Integer) && value >= 0

        raise ArgumentError, "#{name} must be a non-negative Integer, got #{value.inspect}"
      end
    end
  end
end
