# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    class AcceptanceFiller
      def initialize(model_class, attr_name)
        @model_class = model_class
        @attr_name = attr_name.to_s
        @accept_value = nil

        # Process all validators to find acceptance validator. Targets without
        # ActiveModel validators simply have no accepted value to discover.
        validators = model_class.respond_to?(:validators_on) ? model_class.validators_on(attr_name) : []
        validators.each do |validator|
          apply_validator(validator)
        end
      end

      def apply_validator(validator)
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

      def call(_context = nil)
        # Return the accepted value for the acceptance validator
        @accept_value || '1'
      end
    end
  end
end
