# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    class DateTimeFiller
      include ValueResolution
      include NumericConstraintHygiene

      # A pure generator: the constraints arrive already normalized in a
      # ConstraintSet, resolved from the target once at construction.
      def initialize(model_class, attr_name)
        @model_class = model_class
        @attr_name = attr_name.to_s
        @constraints = ConstraintSet.for(model_class, @attr_name)

        # Comparison constraints (raw option forms, resolved at bake time
        # against the object being built)
        bounds = @constraints.comparison_bounds
        @greater_than_attribute = bounds.greater_than
        @greater_than_or_equal_to_attribute = bounds.greater_than_or_equal_to
        @less_than_attribute = bounds.less_than
        @less_than_or_equal_to_attribute = bounds.less_than_or_equal_to
        @equal_to_attribute = bounds.equal_to
        @other_than_attribute = bounds.other_than
      end

      def call(context = nil)
        # 1. Absence validator takes precedence
        return nil if absence_required?

        # 2. Inclusion validator - pick from allowed set
        return pick_from_allowed(context) if allowed_values?

        # 3. Generate a datetime checked against other_than / exclusion
        generate_numeric_value(context) { generate_datetime(context) }
      end

      private

      def pick_from_allowed(context)
        value = pick_from(@constraints.allowed_values, context)
        value.is_a?(DateTime) || value.is_a?(Time) ? value : value.to_datetime
      end

      def generate_datetime(context)
        # Priority 1: Equal to constraint
        equal_to = resolved_datetime_bound(@equal_to_attribute, context)
        return equal_to if equal_to

        # Priority 2: Comparison constraints with other attributes
        lower_bound = calculate_lower_bound(context)
        upper_bound = calculate_upper_bound(context)

        # Priority 3: Attribute name patterns (e.g., created_at, updated_at)
        return generate_by_pattern if lower_bound.nil? && upper_bound.nil?

        generate_in_bounds(lower_bound, upper_bound)
      end

      def resolved_datetime_bound(option, context)
        resolve_datetime_value(resolve_option_value(option, context))
      end

      def calculate_lower_bound(context)
        greater_than_or_equal_to = resolved_datetime_bound(@greater_than_or_equal_to_attribute, context)
        return greater_than_or_equal_to if greater_than_or_equal_to

        greater_than = resolved_datetime_bound(@greater_than_attribute, context)
        return TemporalArithmetic.plus_seconds(greater_than, 1) if greater_than

        nil
      end

      def calculate_upper_bound(context)
        less_than_or_equal_to = resolved_datetime_bound(@less_than_or_equal_to_attribute, context)
        return less_than_or_equal_to if less_than_or_equal_to

        less_than = resolved_datetime_bound(@less_than_attribute, context)
        return TemporalArithmetic.plus_seconds(less_than, -1) if less_than

        nil
      end

      def resolve_other_than(context)
        resolved_datetime_bound(@other_than_attribute, context)
      end

      # The temporal view of `other_than`: only comparison validators write it
      # for datetime attributes.
      def other_than_option
        @other_than_attribute
      end

      def resolve_datetime_value(value)
        case value
        when Symbol, Proc
          # Unresolved reference (no bake-time context): no bound.
          nil
        when Time, DateTime
          # Also catches zoned times: they report themselves as Time.
          value
        when Date
          value.to_time
        when String
          Time.parse(value)
        when Integer
          TemporalArithmetic.plus_seconds(Time.now, value)
        when NilClass
          nil
        else
          value.to_time
        end
      rescue StandardError
        nil
      end

      def generate_in_bounds(lower, upper)
        lower_was_nil = lower.nil?
        upper_was_nil = upper.nil?
        lower ||= TemporalArithmetic.time_plus_years(Time.now, -1)
        upper ||= TemporalArithmetic.time_plus_years(Time.now, 1)

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

        seconds_diff = (upper - lower).to_i
        TemporalArithmetic.plus_seconds(lower, Randomness.rand(0..seconds_diff))
      end

      def generate_by_pattern
        case @attr_name
        when /created_at/
          days_ago(Randomness.rand(0..30))
        when /updated_at/
          days_ago(Randomness.rand(0..7))
        when /published_at|posted_at/
          days_ago(Randomness.rand(0..365))
        when /starts_at|begins_at/
          days_ahead(Randomness.rand(0..30))
        when /ends_at|finishes_at|expires_at/
          days_ahead(Randomness.rand(31..90))
        else
          Time.now
        end
      end

      def days_ago(count)
        TemporalArithmetic.time_plus_days(Time.now, -count)
      end

      def days_ahead(count)
        TemporalArithmetic.time_plus_days(Time.now, count)
      end
    end
  end
end
