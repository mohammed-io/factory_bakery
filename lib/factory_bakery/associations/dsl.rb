# frozen_string_literal: true

module FactoryBakery
  module Associations
    # Mixed into define/trait scope by core's plugin registry. Core routes each
    # call into this plugin's declaration bucket; the plugin evaluates it after
    # instantiation (see Plugin.after_instantiate).
    module DSL
      # Explicit keywords so a later ticket can remove its guard in one place.
      # The signature is the public DSL contract, so it is exempt from the
      # parameter-count cop.
      def association(name, *traits, factory: nil, strategy: nil, count: nil, **overrides, &block) # rubocop:disable Metrics/ParameterLists
        raise ArgumentError, 'strategy: is not supported yet' unless strategy.nil?
        raise ArgumentError, 'count: is not supported yet' unless count.nil?

        record_plugin_declaration(
          Declaration.new(
            name: name.to_sym,
            traits: traits,
            factory: factory,
            overrides: overrides,
            block: block
          )
        )
      end
    end
  end
end
