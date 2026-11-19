# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    class AcceptanceFiller
      # A pure generator: the accepted value arrives already normalized in a
      # ConstraintSet, resolved from the target once at construction.
      def initialize(model_class, attr_name)
        @model_class = model_class
        @attr_name = attr_name.to_s
        @constraints = ConstraintSet.for(model_class, @attr_name)

        # Targets without validators simply have no accepted value to
        # discover; the default below applies.
        @accept_value = @constraints.accept_value
      end

      def call(_context = nil)
        # Return the accepted value for the acceptance validator
        @accept_value || '1'
      end
    end
  end
end
