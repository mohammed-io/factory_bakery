# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    class DateFiller
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

        # 3. Generate a date checked against other_than / exclusion
        generate_numeric_value(context) { generate_date(context) }
      end

      private

      def pick_from_allowed(context)
        value = pick_from(@constraints.allowed_values, context)
        value.is_a?(Date) ? value : value.to_date
      end

      def generate_date(context)
        # Priority 1: Equal to constraint
        equal_to = resolved_date_bound(@equal_to_attribute, context)
        return equal_to if equal_to

        # Priority 2: Comparison constraints with other attributes
        lower_bound = calculate_lower_bound(context)
        upper_bound = calculate_upper_bound(context)

        # Priority 3: Attribute name patterns (e.g., start_date, end_date, birthday)
        return generate_by_pattern if lower_bound.nil? && upper_bound.nil?

        generate_in_bounds(lower_bound, upper_bound)
      end

      def resolved_date_bound(option, context)
        resolve_date_value(resolve_option_value(option, context))
      end

      def calculate_lower_bound(context)
        greater_than_or_equal_to = resolved_date_bound(@greater_than_or_equal_to_attribute, context)
        return greater_than_or_equal_to if greater_than_or_equal_to

        greater_than = resolved_date_bound(@greater_than_attribute, context)
        return TemporalArithmetic.date_plus_days(greater_than, 1) if greater_than

        nil
      end

      def calculate_upper_bound(context)
        less_than_or_equal_to = resolved_date_bound(@less_than_or_equal_to_attribute, context)
        return less_than_or_equal_to if less_than_or_equal_to

        less_than = resolved_date_bound(@less_than_attribute, context)
        return TemporalArithmetic.date_plus_days(less_than, -1) if less_than

        nil
      end

      def resolve_other_than(context)
        resolved_date_bound(@other_than_attribute, context)
      end

      # The temporal view of `other_than`: only comparison validators write it
      # for date attributes.
      def other_than_option
        @other_than_attribute
      end

      def resolve_date_value(value)
        case value
        when Symbol, Proc
          # Unresolved reference (no bake-time context): no bound.
          nil
        when Date
          value
        when Time
          # Also catches zoned times: they report themselves as Time.
          value.to_date
        when String
          Date.parse(value)
        when Integer
          TemporalArithmetic.date_plus_days(Date.today, value)
        when NilClass
          nil
        else
          value.to_date
        end
      rescue StandardError
        nil
      end

      def generate_in_bounds(lower, upper)
        lower_was_nil = lower.nil?
        upper_was_nil = upper.nil?
        lower ||= TemporalArithmetic.date_plus_years(Date.today, -1)
        upper ||= TemporalArithmetic.date_plus_years(Date.today, 1)

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

        days_diff = (upper - lower).to_i
        TemporalArithmetic.date_plus_days(lower, rand(0..days_diff))
      end

      def generate_by_pattern
        case @attr_name
        when /birth|dob|born/
          # Birthday: 18 to 90 years ago
          years_ago(rand(18..90))
        when /start/
          # Start date: within the past year
          days_ago(rand(0..365))
        when /end|expire|due/
          # End date: within the next year
          days_ahead(rand(0..365))
        when /created|at/
          # Created at: recent past
          days_ago(rand(0..30))
        when /updated|at/
          # Updated at: recent past
          days_ago(rand(0..7))
        else
          Date.today
        end
      end

      def days_ago(count)
        TemporalArithmetic.date_plus_days(Date.today, -count)
      end

      def days_ahead(count)
        TemporalArithmetic.date_plus_days(Date.today, count)
      end

      def years_ago(count)
        TemporalArithmetic.date_plus_years(Date.today, -count)
      end
    end
  end
end
