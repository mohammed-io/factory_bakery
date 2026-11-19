# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    class FloatFiller
      include ValueResolution
      include NumericConstraintHygiene

      # A pure generator: the constraints arrive already normalized in a
      # ConstraintSet, resolved from the target once at construction.
      def initialize(model_class, attr_name)
        @model_class = model_class
        @attr_name = attr_name.to_s
        @constraints = ConstraintSet.for(model_class, @attr_name)

        # Schema constraints
        @precision = @constraints.precision
        @scale = @constraints.scale

        # Numericality/comparison constraints (raw option forms, resolved at
        # bake time against the object being built)
        bounds = @constraints.numeric_bounds
        @greater_than = bounds.greater_than
        @greater_than_or_equal_to = bounds.greater_than_or_equal_to
        @equal_to = bounds.equal_to
        @less_than = bounds.less_than
        @less_than_or_equal_to = bounds.less_than_or_equal_to
        @other_than = bounds.other_than
        @in_range = bounds.in_range
      end

      def call(context = nil)
        # 1. Absence validator takes precedence
        return nil if absence_required?

        # 2. Inclusion validator - pick from allowed set
        return pick_from_allowed(context) if allowed_values?

        # 3. Generate value respecting constraints and check the result after
        #    precision/scale has been applied (other_than / exclusion)
        generate_numeric_value(context) { apply_precision_scale(generate_value(context)) }
      end

      private

      def pick_from_allowed(context)
        value = pick_from(@constraints.allowed_values, context)
        value.is_a?(Numeric) ? value : value.to_f
      end

      def generate_value(context)
        # Priority 1: Equal to constraint
        equal_to = resolve_option_value(@equal_to, context)
        return equal_to.to_f if equal_to

        # Priority 2: Range constraint
        in_range = resolve_range(resolve_option_value(@in_range, context), context)
        return generate_in_range(in_range) if in_range

        # Priority 3: Comparison constraints
        lower_bound = calculate_lower_bound(context)
        upper_bound = calculate_upper_bound(context)

        # Priority 4: Attribute name patterns
        return generate_by_pattern if lower_bound.nil? && upper_bound.nil?

        # Generate within bounds
        generate_in_bounds(lower_bound, upper_bound)
      end

      def calculate_lower_bound(context)
        greater_than_or_equal_to = resolve_option_value(@greater_than_or_equal_to, context)
        return greater_than_or_equal_to.to_f if greater_than_or_equal_to

        greater_than = resolve_option_value(@greater_than, context)
        return greater_than.to_f + 0.01 if greater_than

        nil
      end

      def calculate_upper_bound(context)
        less_than_or_equal_to = resolve_option_value(@less_than_or_equal_to, context)
        return less_than_or_equal_to.to_f if less_than_or_equal_to

        less_than = resolve_option_value(@less_than, context)
        return less_than.to_f - 0.01 if less_than

        nil
      end

      def generate_in_range(range)
        # Handle both integer and float ranges
        # Float ranges can't use .to_a directly
        if range.first.is_a?(Float) || range.last.is_a?(Float)
          rand(range.first.to_f..range.last.to_f)
        else
          values = range.to_a
          value = values.sample
          value.to_f
        end
      end

      def generate_in_bounds(lower, upper)
        lower_was_nil = lower.nil?
        upper_was_nil = upper.nil?
        lower ||= 0.0
        upper ||= 100.0

        if lower > upper
          # Extend a default side when only one bound was supplied; swapping
          # would put the generated value outside the supplied constraint.
          if lower_was_nil
            lower = upper
          elsif upper_was_nil
            upper = lower
          else
            lower, upper = upper, lower
          end
        end

        rand(lower..upper)
      end

      def generate_by_pattern
        case @attr_name
        when /rating/
          generate_in_bounds(0.0, 5.0)
        when /percentage/
          generate_in_bounds(0.0, 100.0)
        when /price/
          generate_in_bounds(1.0, 1000.0)
        else
          rand(0.0..100.0)
        end
      end

      def apply_precision_scale(value)
        return value unless @scale

        value.round(@scale)
      end

      def resolve_other_than(context)
        resolved = resolve_option_value(@other_than, context)
        resolved.nil? ? nil : resolved.to_f
      end

      # The numeric view of `other_than` (numericality and comparison
      # validators both write it).
      def other_than_option
        @other_than
      end
    end
  end
end
