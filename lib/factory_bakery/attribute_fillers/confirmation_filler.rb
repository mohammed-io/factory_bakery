# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    class ConfirmationFiller
      def initialize(model_class, attr_name)
        @model_class = model_class
        @attr_name = attr_name.to_s
        @source_attr_name = @attr_name.sub(/_confirmation$/, '')
      end

      def apply_validator(_validator)
        true
      end

      def set_source_value(value)
        @source_value = value
      end

      def call
        # Return the same value as the source attribute
        @source_value || ''
      end
    end
  end
end
