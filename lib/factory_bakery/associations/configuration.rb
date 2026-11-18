# frozen_string_literal: true

module FactoryBakery
  # Opt-in association building. Configuration lives with the plugin so core
  # stays ignorant of it.
  module Associations
    MODES = %i[none required_only all].freeze
    DEFAULT_MAX_DEPTH = 2
    DEFAULT_COUNT = 1

    class << self
      def mode
        @mode ||= :required_only
      end

      def mode=(value)
        unless MODES.include?(value)
          raise ArgumentError, "invalid associations mode #{value.inspect}; expected one of #{MODES.inspect}"
        end

        @mode = value
      end

      # Association hops allowed from the root of one bake. Past this budget
      # :all keeps building only required belongs_to edges so objects stay
      # valid; it never raises for depth alone.
      def max_depth
        @max_depth ||= DEFAULT_MAX_DEPTH
      end

      def max_depth=(value)
        @max_depth = non_negative_integer!(value, :max_depth)
      end

      # Children built per has_many in :all. has_one always builds one.
      def default_count
        @default_count ||= DEFAULT_COUNT
      end

      def default_count=(value)
        @default_count = non_negative_integer!(value, :default_count)
      end

      # The build context counts nested public bakes: the root is depth 1, so
      # its direct association targets are depth 2.
      def past_depth?(context)
        !context.nil? && context.depth > max_depth
      end

      private

      def non_negative_integer!(value, name)
        return value if value.is_a?(Integer) && value >= 0

        raise ArgumentError, "#{name} must be a non-negative Integer, got #{value.inspect}"
      end
    end
  end
end
