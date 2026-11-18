# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    module CommonValidators
      attr_reader :allowed_values, :forbidden_values,
                  :absence_required, :must_be_present

      def apply_common_validator(validator)
        case validator.class.name
        when 'ActiveModel::Validations::InclusionValidator'
          @allowed_values = Array(validator.options[:in])
          true
        when 'ActiveModel::Validations::ExclusionValidator'
          @forbidden_values = Array(validator.options[:in])
          true
        when 'ActiveModel::Validations::PresenceValidator'
          @must_be_present = true
          true
        when 'ActiveModel::Validations::AbsenceValidator', 'ActiveRecord::Validations::AbsenceValidator'
          @absence_required = true
          true
        else
          false
        end
      end

      def pick_from(values)
        case values
        when Array
          values.sample
        when Range
          values.to_a.sample
        when Proc
          pick_from(values.call)
        else
          values
        end
      end

      def absence_required?
        @absence_required == true
      end

      def allowed_values?
        !@allowed_values.nil?
      end

      def forbidden_values?(value)
        @forbidden_values&.include?(value)
      end

      # POROs have no schema and may have no ActiveModel validators either.
      # Schema and validator lookups are optional so fillers can run on any
      # target that exposes the relevant information.
      def column_for(model_class, attr_name)
        return nil unless model_class.respond_to?(:columns_hash)

        model_class.columns_hash[attr_name.to_s]
      end

      def validators_for(model_class, attr_name)
        return [] unless model_class.respond_to?(:validators_on)

        model_class.validators_on(attr_name)
      end
    end
  end
end
