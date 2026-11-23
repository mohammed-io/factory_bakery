# frozen_string_literal: true

require 'set'

module FactoryBakery
  # Announces, through FactoryBakery.logger at WARN, that a remote-URL writer
  # was left blank on purpose (see AttributeFillers::GuardedWriterFiller). Each
  # model class and attribute is announced once per process, so a suite that
  # bakes the same model many times sees one line, not one per bake.
  module RemoteUrlNotice
    class << self
      def announce(model_class, attr_name)
        return unless announced.add?([model_class, attr_name.to_s])

        FactoryBakery.logger&.warn(message(model_class, attr_name))
      end

      private

      def announced
        @announced ||= Set.new
      end

      def message(model_class, attr_name)
        "left #{model_class}##{attr_name} blank on purpose: assigning it downloads the URL. " \
          'Set it in a definition or pass it as an override to fill it.'
      end
    end
  end
end
