# frozen_string_literal: true

module FactoryBakery
  # Opt-in association building. Configuration lives with the plugin so core
  # stays ignorant of it.
  module Associations
    MODES = %i[none required_only all].freeze

    class << self
      # :required_only is the approved default, but only :none is implemented
      # in this slice. Values other than :none are accepted here and behave
      # exactly like :none until their tickets land.
      def mode
        @mode ||= :required_only
      end

      def mode=(value)
        unless MODES.include?(value)
          raise ArgumentError, "invalid associations mode #{value.inspect}; expected one of #{MODES.inspect}"
        end

        @mode = value
      end
    end
  end
end
