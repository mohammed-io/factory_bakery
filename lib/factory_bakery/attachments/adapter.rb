# frozen_string_literal: true

module FactoryBakery
  module Attachments
    # Picks the first adapter whose library is loaded and that knows
    # attachments on this class. Every framework-specific read lives in an
    # adapter; the plugin only orchestrates.
    module Adapter
      ADAPTERS = [Adapters::ActiveStorage, Adapters::Paperclip].freeze

      module_function

      def for(klass)
        ADAPTERS.find { |adapter| adapter.available?(klass) && adapter.names(klass).any? }
      end
    end
  end
end
