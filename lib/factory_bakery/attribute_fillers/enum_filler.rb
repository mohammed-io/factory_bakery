# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    class EnumFiller
      include ValueResolution

      # A pure generator: enum membership and values arrive already normalized
      # in a ConstraintSet, resolved from the target once at construction.
      def initialize(model_class, attr_name)
        @model_class = model_class
        @attr_name = attr_name.to_s
        @constraints = ConstraintSet.for(model_class, @attr_name)

        # Enum mapping (string values to integer indices), normalized by the
        # reader from the target's enum registry (or an equivalent string
        # inclusion).
        @enum_values = @constraints.enum_values
      end

      def call(context = nil)
        # 1. Absence validator takes precedence
        return nil if absence_required?

        # 2. Inclusion validator (explicit) - pick from allowed set. An
        # inclusion set identical to the enum's values is the enum itself
        # (some frameworks materialize enums that way), so only a different
        # set wins over the enum.
        return pick_from_allowed(context) if allowed_values? && @constraints.allowed_values != @enum_values

        # 3. Pick from enum values
        pick_from_enum
      end

      private

      def pick_from_allowed(context)
        pick_from(@constraints.allowed_values, context)
      end

      def pick_from_enum
        return nil if @enum_values.empty?

        @enum_values.sample
      end
    end
  end
end
