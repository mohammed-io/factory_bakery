# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    class BooleanFiller
      include ValueResolution

      # A pure generator: the constraints arrive already normalized in a
      # ConstraintSet, resolved from the target once at construction.
      def initialize(model_class, attr_name)
        @model_class = model_class
        @attr_name = attr_name.to_s
        @constraints = ConstraintSet.for(model_class, @attr_name)

        # Acceptance validator specific
        @accept_value = @constraints.accept_value
      end

      def call(context = nil)
        # 1. Absence validator takes precedence
        return nil if absence_required?

        # 2. Inclusion validator - pick from allowed set
        return pick_from_allowed(context) if allowed_values?

        # 3. Acceptance validator - return the accept value if set
        return @accept_value unless @accept_value.nil?

        # 4. A presence-validated boolean must be true: false is treated as
        #    blank, so sampling both values fails presence half the time.
        return true if must_be_present?

        # 5. Generate boolean value
        generate_boolean
      end

      private

      def pick_from_allowed(context)
        allowed = resolve_set(@constraints.allowed_values, context, 'inclusion')
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
        Randomness.sample([true, false])
      end
    end
  end
end
