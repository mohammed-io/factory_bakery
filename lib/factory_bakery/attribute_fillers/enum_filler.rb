# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    class EnumFiller
      include CommonValidators

      def initialize(model_class, attr_name)
        @model_class = model_class
        @attr_name = attr_name.to_s

        # Schema constraints
        @column = model_class.columns_hash[@attr_name]
        @nullable = @column&.null
        @has_default = @column&.default

        # Enum mapping (string values to integer indices)
        @enum_values = []

        # Common validator attributes
        @allowed_values = nil
        @forbidden_values = nil
        @must_be_present = false
        @absence_required = false

        # Detect and load enum definition
        load_enum_definition

        # Process all validators
        model_class.validators_on(attr_name).each do |validator|
          apply_validator(validator)
        end
      end

      def apply_validator(validator)
        apply_common_validator(validator)
      end

      def call
        # 1. Absence validator takes precedence
        return nil if absence_required?

        # 2. Inclusion validator (explicit) - pick from allowed set
        return pick_from_allowed if allowed_values? && @allowed_values != @enum_values

        # 3. Pick from enum values
        pick_from_enum
      end

      private

      def load_enum_definition
        # Rails 5+ stores enum definitions in defined_enums
        @enum_values = @model_class.defined_enums[@attr_name]&.keys || [] if @model_class.respond_to?(:defined_enums)

        # Rails 4 used pluralized_versions attribute
        if @enum_values.empty? && @model_class.respond_to?(:pluralized_enum_values)
          pluralized_name = @attr_name.pluralize
          @enum_values = @model_class.pluralized_enum_values[pluralized_name]&.keys || []
        end

        # Fallback: try to detect from inclusion validator with string array
        return unless @enum_values.empty?

        @model_class.validators_on(@attr_name).each do |validator|
          next unless validator.instance_of?(ActiveModel::Validations::InclusionValidator)

          values = validator.options[:in]
          if values.is_a?(Array) && values.all? { |v| v.is_a?(String) }
            @enum_values = values
            break
          end
        end
      end

      def pick_from_allowed
        pick_from(@allowed_values)
      end

      def pick_from_enum
        return nil if @enum_values.empty?

        @enum_values.sample
      end
    end
  end
end
