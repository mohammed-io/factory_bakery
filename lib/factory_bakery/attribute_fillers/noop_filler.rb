# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    class NoopFiller
      def initialize(model_class, attr_name); end

      def apply_validator(_validator)
        true
      end

      def call
        nil
      end
    end
  end
end
