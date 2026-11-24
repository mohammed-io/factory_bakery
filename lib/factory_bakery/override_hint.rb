# frozen_string_literal: true

module FactoryBakery
  # The "what to do next" part of an error raised when a value cannot be
  # generated: the two ways to give the attribute a value yourself, spelled out
  # as code a person (or a coding agent) can paste, with the model and
  # attribute filled in.
  module OverrideHint
    class << self
      # `value_hint` describes the value to write, for example
      # "a value matching /\A[A-Z]{3}\z/".
      def call(model_class, attribute, value_hint, see: 'format-exhaustion')
        model = model_class.respond_to?(:name) && model_class.name ? model_class.name : model_class.inspect
        placeholder = "'<#{value_hint}>'"
        "Give #{attribute} a value yourself. In the factory definition:\n" \
          "  FactoryBakery.define(#{model}) do\n" \
          "    #{attribute} { #{placeholder} }\n" \
          "  end\n" \
          "or for one call:\n" \
          "  FactoryBakery.bake(#{model}, #{attribute}: #{placeholder})\n" \
          "See docs/diagnostics.md##{see}."
      end
    end
  end
end
