# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    class DateTimeFiller
      include CommonValidators

      def initialize(model_class, attr_name)
        @model_class = model_class
        @attr_name = attr_name.to_s

        # Schema constraints
        @column = model_class.columns_hash[@attr_name]
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
        model_class.validators_on(attr_name).each do |validator|
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

      def call
        # 1. Absence validator takes precedence
        return nil if absence_required?

        # 2. Inclusion validator - pick from allowed set
        return pick_from_allowed if allowed_values?

        # 3. Generate datetime respecting constraints
        generate_datetime
      end

      private

      def apply_comparison_validator(opts)
        @greater_than_attribute = resolve_comparison_value(opts[:greater_than])
        @greater_than_or_equal_to_attribute = resolve_comparison_value(opts[:greater_than_or_equal_to])
        @less_than_attribute = resolve_comparison_value(opts[:less_than])
        @less_than_or_equal_to_attribute = resolve_comparison_value(opts[:less_than_or_equal_to])
        @equal_to_attribute = resolve_comparison_value(opts[:equal_to])
        @other_than_attribute = resolve_comparison_value(opts[:other_than])
      end

      def resolve_comparison_value(value)
        case value
        when Symbol
          value # Reference to another attribute
        when Proc
          value.call
        else
          value
        end
      end

      def pick_from_allowed
        value = pick_from(@allowed_values)
        value.is_a?(DateTime) || value.is_a?(Time) ? value : value.to_datetime
      end

      def generate_datetime
        # Priority 1: Equal to constraint
        return resolve_datetime_value(@equal_to_attribute) if @equal_to_attribute

        # Priority 2: Comparison constraints with other attributes
        lower_bound = calculate_lower_bound
        upper_bound = calculate_upper_bound

        # Priority 3: Attribute name patterns (e.g., created_at, updated_at)
        return generate_by_pattern if lower_bound.nil? && upper_bound.nil?

        generate_in_bounds(lower_bound, upper_bound)
      end

      def calculate_lower_bound
        if @greater_than_or_equal_to_attribute
          resolve_datetime_value(@greater_than_or_equal_to_attribute)
        elsif @greater_than_attribute
          resolve_datetime_value(@greater_than_attribute) + 1.second
        end
      end

      def calculate_upper_bound
        if @less_than_or_equal_to_attribute
          resolve_datetime_value(@less_than_or_equal_to_attribute)
        elsif @less_than_attribute
          resolve_datetime_value(@less_than_attribute) - 1.second
        end
      end

      def resolve_datetime_value(value)
        case value
        when Symbol
          # Reference to another attribute - not supported without context
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
        lower ||= Time.now - 1.year
        upper ||= Time.now + 1.year

        # Swap if bounds are inverted
        lower, upper = upper, lower if lower > upper

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
