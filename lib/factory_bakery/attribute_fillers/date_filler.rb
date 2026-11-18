# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    class DateFiller
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

        # 3. Generate date respecting constraints
        generate_date
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
        value.is_a?(Date) ? value : value.to_date
      end

      def generate_date
        # Priority 1: Equal to constraint
        return resolve_date_value(@equal_to_attribute) if @equal_to_attribute

        # Priority 2: Comparison constraints with other attributes
        lower_bound = calculate_lower_bound
        upper_bound = calculate_upper_bound

        # Priority 3: Attribute name patterns (e.g., start_date, end_date, birthday)
        return generate_by_pattern if lower_bound.nil? && upper_bound.nil?

        generate_in_bounds(lower_bound, upper_bound)
      end

      def calculate_lower_bound
        if @greater_than_or_equal_to_attribute
          resolve_date_value(@greater_than_or_equal_to_attribute)
        elsif @greater_than_attribute
          resolve_date_value(@greater_than_attribute) + 1.day
        end
      end

      def calculate_upper_bound
        if @less_than_or_equal_to_attribute
          resolve_date_value(@less_than_or_equal_to_attribute)
        elsif @less_than_attribute
          resolve_date_value(@less_than_attribute) - 1.day
        end
      end

      def resolve_date_value(value)
        case value
        when Symbol
          # Reference to another attribute - not supported without context
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
        lower ||= Date.today - 1.year
        upper ||= Date.today + 1.year

        # Swap if bounds are inverted
        lower, upper = upper, lower if lower > upper

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
