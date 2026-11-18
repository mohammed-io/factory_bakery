# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    module CommonValidators
      attr_reader :allowed_values, :forbidden_values, :unique_required,
                  :absence_required, :must_be_present

      def apply_common_validator(validator)
        case validator.class.name
        when 'ActiveModel::Validations::InclusionValidator'
          @allowed_values = Array(validator.options[:in])
          true
        when 'ActiveModel::Validations::ExclusionValidator'
          @forbidden_values = Array(validator.options[:in])
          true
        when 'ActiveRecord::Validations::UniquenessValidator'
          @unique_required = true
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

      def unique_required?
        @unique_required == true
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
    end
  end
end
