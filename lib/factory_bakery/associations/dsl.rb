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
      #
      # The target class may lead the positional arguments instead of being
      # passed as factory: (`association :post, Post, :published`); traits are
      # always symbols, so a Class there is unambiguous.
      #
      # `with:` holds the attribute overrides for the built target, kept apart
      # from the association's own options so a key such as `user:` cannot be
      # read as one of them, and a column named `count` can still be set.
      #
      # `persist: true` saves a belongs_to target before the owner is
      # validated, even under plain `bake`, for validators that read the
      # parent's id (like FactoryBot's `strategy: :create` on an association).
      def association(name, *traits, factory: nil, strategy: nil, count: nil, persist: false, with: {}, # rubocop:disable Metrics/ParameterLists
                      **unknown, &block)
        reject_unknown!(unknown)
        factory, traits = positional_target(traits, factory)
        Associations.validated_strategy!(strategy) unless strategy.nil?
        validate_count!(count)
        validate_with!(with)
        validate_persist!(persist, block)
        validate_block!(block, count, traits, factory, with)

        # Frozen, and read-only for the plugin. The entry is replayed to
        # every later bake only when its `with:` values are safe to share
        # (see reusable_overrides?); otherwise the layer that declared it is
        # evaluated on every bake, so each bake gets its own values.
        record_plugin_declaration(
          Declaration.new(
            name: name.to_sym,
            traits: traits.freeze,
            factory: factory,
            child_count: count,
            overrides: with.dup.freeze,
            block: block,
            strategy: strategy,
            persist: persist
          ).freeze,
          reusable: reusable_overrides?(with)
        )
      end

      private

      # An entry is replayed to every later bake, so its `with:` values are
      # shared between them. Only values that cannot change under sharing may
      # promise reusability: nil, true, false, Integer, Float, Symbol, a
      # frozen String, a Class or Module, a Range of those, or a frozen
      # Array/Hash whose members qualify in turn. A mutable value (an
      # unfrozen String, a record a caller supplied) belongs to the bake that
      # created it -- a later setter could mutate it in place for every
      # replayed entry -- so such a `with:` makes the entry non-reusable and
      # the layer that declared it is evaluated on every bake (ADR-0008).
      def reusable_overrides?(with)
        with.each_value { |value| return false unless reusable_value?(value) }
        true
      end

      # The classification walks a value's structure, so it branches by kind;
      # each branch is one line and the recursion is bounded by the value's
      # nesting.
      # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      def reusable_value?(value)
        case value
        when nil, true, false, Integer, Float, Symbol, Class, Module
          true
        when String
          value.frozen?
        when Range
          reusable_value?(value.begin) && reusable_value?(value.end)
        when Array
          value.frozen? && value.all? { |member| reusable_value?(member) }
        when Hash
          value.frozen? && value.all? { |key, member| reusable_value?(key) && reusable_value?(member) }
        else
          false
        end
      end
      # rubocop:enable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

      # Overrides passed beside the options (the FactoryBot spelling) are
      # refused with the spelling that works.
      def reject_unknown!(unknown)
        return if unknown.empty?

        raise ArgumentError,
              "unknown association option(s) #{unknown.keys.map { "#{_1}:" }.join(', ')}; " \
              "pass attribute overrides as with: #{unknown.inspect}"
      end

      def positional_target(traits, factory)
        return [factory, traits] unless traits.first.is_a?(Class)
        raise ArgumentError, 'pass the target class positionally or as factory:, not both' unless factory.nil?

        [traits.first, traits.drop(1)]
      end

      def validate_with!(with)
        raise ArgumentError, 'with: must be a Hash of attribute overrides' unless with.is_a?(Hash)
      end

      # A block returns the finished value, so it alone decides whether that
      # value is saved.
      def validate_persist!(persist, block)
        raise ArgumentError, 'persist: must be true or false' unless [true, false].include?(persist)
        return unless persist && block

        raise ArgumentError, 'a block cannot be combined with persist:; call bake! inside the block'
      end

      def validate_count!(count)
        return if count.nil? || (count.is_a?(Integer) && count >= 0)

        raise ArgumentError, 'count: must be a non-negative Integer'
      end

      # A block decides the whole value from the owner, so combining it with
      # options that would also decide the children is ambiguous.
      def validate_block!(block, count, traits, factory, with)
        return unless block
        return if count.nil? && traits.empty? && factory.nil? && with.empty?

        raise ArgumentError, 'a block cannot be combined with count:, traits, factory: or with:'
      end
    end
  end
end
