# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    class DateFiller
      include CommonValidators
      include NumericConstraintHygiene

      def initialize(model_class, attr_name)
        @model_class = model_class
        @attr_name = attr_name.to_s

        # Schema constraints
        @column = column_for(model_class, attr_name)
        @nullable = @column&.null
        @has_default = @column&.default

        # Comparison constraints
        @greater_than_attribute = nil
        @greater_than_or_equal_to_attribute = nil
        @less_than_attribute = nil
        @less_than_or_equal_to_attribute = nil
        @equal_to_attribute = nil
        @other_than_attribute = nil

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

        # 3. Generate a date checked against other_than / exclusion
        generate_numeric_value(context) { generate_date(context) }
      end

      private

      def apply_comparison_validator(opts)
        # Keep the raw Rails option forms; symbols and procs are resolved at
        # bake time against the object being built, not at filler creation.
        @greater_than_attribute = opts[:greater_than]
        @greater_than_or_equal_to_attribute = opts[:greater_than_or_equal_to]
        @less_than_attribute = opts[:less_than]
        @less_than_or_equal_to_attribute = opts[:less_than_or_equal_to]
        @equal_to_attribute = opts[:equal_to]
        @other_than_attribute = opts[:other_than]
      end

      def pick_from_allowed(context)
        value = pick_from(@allowed_values, context)
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
        return greater_than + 1.day if greater_than

        nil
      end

      def calculate_upper_bound(context)
        less_than_or_equal_to = resolved_date_bound(@less_than_or_equal_to_attribute, context)
        return less_than_or_equal_to if less_than_or_equal_to

        less_than = resolved_date_bound(@less_than_attribute, context)
        return less_than - 1.day if less_than

        nil
      end

      def resolve_other_than(context)
        resolved_date_bound(@other_than_attribute, context)
      end

      def resolve_date_value(value)
        case value
        when Symbol, Proc
          # Unresolved reference (no bake-time context): no bound.
          nil
        when Date
          value
        when Time, DateTime, ActiveSupport::TimeWithZone
          value.to_date
        when String
          Date.parse(value)
        when Integer
          Date.today + value.days
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
        lower ||= Date.today - 1.year
        upper ||= Date.today + 1.year

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
        lower + rand(0..days_diff).days
      end

      def generate_by_pattern
        case @attr_name
        when /birth|dob|born/
          # Birthday: 18 to 90 years ago
          Date.today - rand(18..90).years
        when /start/
          # Start date: within the past year
          Date.today - rand(0..365).days
        when /end|expire|due/
          # End date: within the next year
          Date.today + rand(0..365).days
        when /created|at/
          # Created at: recent past
          Date.today - rand(0..30).days
        when /updated|at/
          # Updated at: recent past
          Date.today - rand(0..7).days
        else
          Date.today
        end
      end
    end
  end
end
