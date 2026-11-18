# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    # Bake-time resolution of comparison/numericality options that reference
    # other attributes (Symbols) or are computed lazily (Procs).
    #
    # Fillers receive one of these as `call(context)` and ask for a referenced
    # attribute with `value_for(:name)`. Explicitly supplied values (overrides,
    # declarations, initialize_with, plugin values, counter caches) win; every
    # other attribute is generated on first use, so a reference to an attribute
    # that appears later in column order still sees its final value. Generated
    # values are cached and assigned to the object being built, so record-aware
    # Procs can read them as well.
    #
    # A cycle (two attributes referencing each other) resolves the back edge to
    # nil: that bound is treated as absent and the attribute is generated
    # unconstrained instead of raising.
    class BakeTimeValues
      attr_reader :object, :values

      def initialize(model_class, explicit_values, skipped_names, object)
        @model_class = model_class
        @explicit_values = stringify_keys(explicit_values)
        @skipped_names = skipped_names.map(&:to_s).freeze
        @object = object
        @values = {}
        @resolving = []
      end

      def value_for(name)
        key = name.to_s
        return @explicit_values[key] if @explicit_values.key?(key)
        return @values[key] if @values.key?(key)
        return nil if @skipped_names.include?(key)
        return nil if @resolving.include?(key)

        generate(key)
      end

      private

      def generate(key)
        @resolving << key
        filler = FillerSelector.new(@model_class, key).call
        # Same exclusions as the builder's old heuristic pass: these fillers
        # never contribute an assigned value to the object.
        return nil if filler.is_a?(NoopFiller) || filler.is_a?(ConfirmationFiller)

        value = filler.call(self)
        @values[key] = value
        assign_to_object(key, value)
        value
      ensure
        @resolving.pop
      end

      def assign_to_object(key, value)
        setter = "#{key}="
        @object.public_send(setter, value) if @object&.respond_to?(setter)
      end

      def stringify_keys(hash)
        (hash || {}).each_with_object({}) { |(key, value), result| result[key.to_s] = value }
      end
    end
  end
end
