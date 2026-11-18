# frozen_string_literal: true

module FactoryBakery
  module Associations
    # Mixed into define/trait scope by core's plugin registry. Core routes each
    # call into this plugin's declaration bucket; the plugin evaluates it after
    # instantiation (see Plugin.after_instantiate).
    module DSL
      def association(name)
        record_plugin_declaration(name.to_sym)
      end
    end
  end
end
