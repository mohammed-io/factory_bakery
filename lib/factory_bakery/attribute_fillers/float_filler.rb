# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    class FloatFiller
      include CommonValidators

      def initialize(model_class, attr_name)
        @model_class = model_class
        @attr_name = attr_name.to_s

        # Schema constraints
        @column = column_for(model_class, attr_name)
        @nullable = @column&.null
        @has_default = @column&.default
        @precision = @column&.precision
        @scale = @column&.scale

        # Numericality constraints
        @greater_than = nil
        @greater_than_or_equal_to = nil
        @equal_to = nil
        @less_than = nil
        @less_than_or_equal_to = nil
        @other_than = nil
        @in_range = nil

        # Common validator attributes
        @allowed_values = nil
        @forbidden_values = nil
        @must_be_present = false
        @absence_required = false

        # Process all validators
        validators_for(model_class, attr_name).each do |validator|
          apply_validator(validator)
        end
      end

      def apply_validator(validator)
        return true if apply_common_validator(validator)

        case validator.class.name
        when 'ActiveModel::Validations::NumericalityValidator', 'ActiveRecord::Validations::NumericalityValidator'
          apply_numericality_validator(validator.options)
        when 'ActiveModel::Validations::ComparisonValidator'
          apply_comparison_validator(validator.options)
        else
          false
        end
      end

      def call(context = nil)
        # 1. Absence validator takes precedence
        return nil if absence_required?

        # 2. Inclusion validator - pick from allowed set
        return pick_from_allowed(context) if allowed_values?

        # 3. Generate value respecting constraints
        value = generate_value(context)

        # 4. Apply precision/scale if specified
        value = apply_precision_scale(value)

        # 5. Ensure not in exclusion set
        avoid_forbidden(value, context)
      end

      private

      def apply_numericality_validator(opts)
        @greater_than = opts[:greater_than]
        @greater_than_or_equal_to = opts[:greater_than_or_equal_to]
        @equal_to = opts[:equal_to]
        @less_than = opts[:less_than]
        @less_than_or_equal_to = opts[:less_than_or_equal_to]
        @other_than = opts[:other_than]
        @in_range = opts[:in]
      end

      def apply_comparison_validator(opts)
        @greater_than = opts[:greater_than]
        @greater_than_or_equal_to = opts[:greater_than_or_equal_to]
        @equal_to = opts[:equal_to]
        @less_than = opts[:less_than]
        @less_than_or_equal_to = opts[:less_than_or_equal_to]
        @other_than = opts[:other_than]
        @in_range = opts[:in] if opts[:in]
      end

      def pick_from_allowed(context)
        value = pick_from(@allowed_values, context)
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

      def avoid_forbidden(value, context)
        return value unless @forbidden_values

        attempts = 0
        while forbidden_values?(value, context) && attempts < 20
          value = generate_value(context)
          value = apply_precision_scale(value)
          attempts += 1
        end
        value
      end
    end
  end
end
