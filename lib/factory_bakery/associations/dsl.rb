# frozen_string_literal: true

module FactoryBakery
  module Associations
    # Mixed into define/trait scope by core's plugin registry. Core routes each
    # call into this plugin's declaration bucket; the plugin evaluates it after
    # instantiation (see Plugin.after_instantiate).
    module DSL
      # Explicit keywords keep the public DSL contract in one place. It is
      # exempt from the parameter-count cop because every keyword is part of
      # that contract.
      def association(name, *traits, factory: nil, strategy: nil, count: nil, **overrides, &block) # rubocop:disable Metrics/ParameterLists
        Associations.validated_strategy!(strategy) unless strategy.nil?
        validate_count!(count)
        validate_block!(block, count, traits, factory, overrides)

        record_plugin_declaration(
          Declaration.new(
            name: name.to_sym,
            traits: traits,
            factory: factory,
            child_count: count,
            overrides: overrides,
            block: block,
            strategy: strategy
          )
        )
      end

      private

      def validate_count!(count)
        return if count.nil? || (count.is_a?(Integer) && count >= 0)

        raise ArgumentError, 'count: must be a non-negative Integer'
      end

      # A block decides the whole value from the owner, so combining it with
      # options that would also decide the children is ambiguous.
      def validate_block!(block, count, traits, factory, overrides)
        return unless block
        return if count.nil? && traits.empty? && factory.nil? && overrides.empty?

        raise ArgumentError, 'a block cannot be combined with count:, traits, factory: or attribute overrides'
      end
    end
  end
end
