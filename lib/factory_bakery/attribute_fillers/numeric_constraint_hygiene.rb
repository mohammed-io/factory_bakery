# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    # Shared machinery for the three numeric-hygiene guarantees:
    #   * `other_than` is checked, not merely stored;
    #   * candidates are regenerated (bounded) until every constraint holds;
    #   * exhaustion raises a contextual error instead of leaking a value the
    #     model's validators would reject.
    #
    # The budget matches the uniqueness enforcer and the string filler's format
    # verification so every bounded-retry path in a bake fails the same way.
    module NumericConstraintHygiene
      MAX_ATTEMPTS = 10

      private

      # Generate candidates until one satisfies every post-generation check.
      # A value is never returned unverified; exhaustion raises instead.
      def generate_numeric_value(context)
        attempts = 0
        loop do
          value = yield
          return value if numeric_compliant?(value, context)

          attempts += 1
          raise numeric_exhaustion_error(value) if attempts >= MAX_ATTEMPTS
        end
      end

      def numeric_compliant?(value, context)
        return false if value.nil?
        return false if violates_other_than?(value, context)
        return false if forbidden_values?(value, context)

        true
      end

      # Resolved at bake time so Proc/Symbol options keep working (V3 machinery)
      # and nil (an unresolved reference) means "no constraint".
      def resolve_other_than(context)
        resolve_option_value(other_than_option, context)
      end

      def other_than_option
        return @other_than if defined?(@other_than) && !@other_than.nil?
        return @other_than_attribute if defined?(@other_than_attribute) && !@other_than_attribute.nil?

        nil
      end

      def violates_other_than?(value, context)
        forbidden = resolve_other_than(context)
        !forbidden.nil? && value == forbidden
      end

      def numeric_exhaustion_error(value)
        numeric_constraint_error(
          value,
          "#{numeric_constraint_description} after #{MAX_ATTEMPTS} attempts"
        )
      end

      def numeric_constraint_error(value, detail)
        FactoryBakery::Error.new(
          "could not generate a value satisfying the numeric constraints for " \
          "#{@model_class}##{@attr_name} (#{detail}): #{value.inspect} violates " \
          'the constraints. Pass an explicit value with an override or relax them.'
        )
      end

      def numeric_constraint_description
        parts = []
        parts << "other_than: #{other_than_option.inspect}" if other_than_option
        parts << "exclusion: #{@forbidden_values.inspect}" if @forbidden_values
        parts << 'even: true' if defined?(@even_only) && @even_only
        parts << 'odd: true' if defined?(@odd_only) && @odd_only
        parts.join(', ')
      end
    end
  end
end
