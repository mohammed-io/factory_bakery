# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    class DateTimeFiller
      include CommonValidators

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
        return pick_from_allowed if allowed_values?

        # 3. Generate datetime respecting constraints
        generate_datetime(context)
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

      def pick_from_allowed
        value = pick_from(@allowed_values)
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
        return greater_than + 1.second if greater_than

        nil
      end

      def calculate_upper_bound(context)
        less_than_or_equal_to = resolved_datetime_bound(@less_than_or_equal_to_attribute, context)
        return less_than_or_equal_to if less_than_or_equal_to

        less_than = resolved_datetime_bound(@less_than_attribute, context)
        return less_than - 1.second if less_than

        nil
      end

      def resolve_datetime_value(value)
        case value
        when Symbol, Proc
          # Unresolved reference (no bake-time context): no bound.
          nil
        when Time, DateTime, ActiveSupport::TimeWithZone
          value
        when Date
          value.to_time
        when String
          Time.parse(value)
        when Integer
          Time.now + value.seconds
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
        lower ||= Time.now - 1.year
        upper ||= Time.now + 1.year

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
        lower + rand(0..seconds_diff).seconds
      end

      def generate_by_pattern
        case @attr_name
        when /created_at/
          Time.now - rand(0..30).days
        when /updated_at/
          Time.now - rand(0..7).days
        when /published_at|posted_at/
          Time.now - rand(0..365).days
        when /starts_at|begins_at/
          Time.now + rand(0..30).days
        when /ends_at|finishes_at|expires_at/
          Time.now + rand(31..90).days
        else
          Time.now
        end
      end
    end
  end
end
