# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    class IntegerFiller
      include CommonValidators

      def initialize(model_class, attr_name)
        @model_class = model_class
        @attr_name = attr_name.to_s

        # Schema constraints
        @column = column_for(model_class, attr_name)
        @nullable = @column&.null
        @has_default = @column&.default

        # Numericality constraints
        @greater_than = nil
        @greater_than_or_equal_to = nil
        @equal_to = nil
        @less_than = nil
        @less_than_or_equal_to = nil
        @other_than = nil
        @odd_only = false
        @even_only = false
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

      def call
        # 1. Absence validator takes precedence
        return nil if absence_required?

        # 2. Inclusion validator - pick from allowed set
        return pick_from_allowed if allowed_values?

        # 3. Generate value respecting constraints
        value = generate_value

        # 4. Ensure not in exclusion set
        avoid_forbidden(value)
      end

      private

      def apply_numericality_validator(opts)
        @greater_than = opts[:greater_than]
        @greater_than_or_equal_to = opts[:greater_than_or_equal_to]
        @equal_to = opts[:equal_to]
        @less_than = opts[:less_than]
        @less_than_or_equal_to = opts[:less_than_or_equal_to]
        @other_than = opts[:other_than]
        @odd_only = opts[:odd] || false
        @even_only = opts[:even] || false
        @in_range = opts[:in]
      end

      def apply_comparison_validator(opts)
        @greater_than = opts[:greater_than]
        @greater_than_or_equal_to = opts[:greater_than_or_equal_to]
        @equal_to = opts[:equal_to]
        @less_than = opts[:less_than]
        @less_than_or_equal_to = opts[:less_than_or_equal_to]
        @other_than = opts[:other_than]
      end

      def pick_from_allowed
        pick_from(@allowed_values).to_i
      end

      def generate_value
        # Priority 1: Equal to constraint
        return @equal_to.to_i if @equal_to

        # Priority 2: Range constraint
        return generate_in_range if @in_range

        # Priority 3: Comparison constraints
        lower_bound = calculate_lower_bound
        upper_bound = calculate_upper_bound

        # Priority 4: Attribute name patterns
        return generate_by_pattern if lower_bound.nil? && upper_bound.nil?

        # Generate within bounds
        generate_in_bounds(lower_bound, upper_bound)
      end

      def calculate_lower_bound
        if @greater_than_or_equal_to
          @greater_than_or_equal_to.to_i
        elsif @greater_than
          @greater_than.to_i + 1
        end
      end

      def calculate_upper_bound
        if @less_than_or_equal_to
          @less_than_or_equal_to.to_i
        elsif @less_than
          @less_than.to_i - 1
        end
      end

      def generate_in_range
        values = @in_range.to_a
        value = values.sample
        apply_odd_even_constraint(value.to_i)
      end

      def generate_in_bounds(lower, upper)
        lower ||= 0
        upper ||= 100

        # Swap if bounds are inverted
        lower, upper = upper, lower if lower > upper

        value = rand(lower..upper)
        apply_odd_even_constraint(value)
      end

      def generate_by_pattern
        case @attr_name
        when /age|priority/
          generate_in_bounds(18, 65)
        when /score|rating|percentage/
          generate_in_bounds(0, 100)
        when /quantity/
          generate_in_bounds(1, 100)
        when /price/
          generate_in_bounds(1, 1000)
        when /number/
          generate_in_bounds(1, 999)
        else
          apply_odd_even_constraint(rand(1..100))
        end
      end

      def apply_odd_even_constraint(value)
        if @odd_only
          value.even? ? value + 1 : value
        elsif @even_only
          value.odd? ? value + 1 : value
        else
          value
        end
      end

      def avoid_forbidden(value)
        return value unless @forbidden_values

        attempts = 0
        while forbidden_values?(value) && attempts < 20
          value = generate_value
          attempts += 1
        end
        value
      end
    end
  end
end
