# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    class BooleanFiller
      include CommonValidators

      def initialize(model_class, attr_name)
        @model_class = model_class
        @attr_name = attr_name.to_s

        # Schema constraints
        @column = column_for(model_class, attr_name)
        @nullable = @column&.null
        @has_default = @column&.default

        # Acceptance validator specific
        @accept_value = nil

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
        when 'ActiveModel::Validations::AcceptanceValidator', 'ActiveRecord::Validations::AcceptanceValidator'
          accept_opt = validator.options[:accept]
          # Handle array of accepted values (Rails default: ["1", true])
          @accept_value = if accept_opt.is_a?(Array)
                           accept_opt.first # Pick the first value (usually '1')
                         else
                           accept_opt
                         end
          true
        else
          false
        end
      end

      def call(context = nil)
        # 1. Absence validator takes precedence
        return nil if absence_required?

        # 2. Inclusion validator - pick from allowed set
        return pick_from_allowed(context) if allowed_values?

        # 3. Acceptance validator - return the accept value if set
        return @accept_value unless @accept_value.nil?

        # 4. Rails treats false as blank, so a presence-validated boolean
        #    must be true; sampling both values fails presence half the time.
        return true if must_be_present?

        # 5. Generate boolean value
        generate_boolean
      end

      private

      def pick_from_allowed(context)
        allowed = resolve_set(@allowed_values, context, 'inclusion')
        value = pick_from(allowed, context)
        # If all allowed values are strings, return the string as-is
        return value if allowed.all? { |v| v.is_a?(String) }

        # Convert to boolean if needed
        case value
        when '1', 1, true, 'true' then true
        when '0', 0, false, 'false' then false
        else
          # Return as-is for custom acceptance values
          value
        end
      end

      def generate_boolean
        # Special case for terms/acceptance attributes
        return @accept_value || '1' if @attr_name.match?(/terms|accepted|agreed/)

        # Random boolean
        [true, false].sample
      end
    end
  end
end
