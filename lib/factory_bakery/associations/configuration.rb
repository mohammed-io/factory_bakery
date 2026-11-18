# frozen_string_literal: true

module FactoryBakery
  # Opt-in association building. Configuration lives with the plugin so core
  # stays ignorant of it.
  module Associations
    MODES = %i[none required_only all].freeze

    class << self
      # :required_only is the default once the plugin is loaded. :none and
      # :all are accepted here; :all behaves like :none until its ticket lands.
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
