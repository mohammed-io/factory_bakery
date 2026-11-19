# frozen_string_literal: true

module FactoryBakery
  module ActiveRecordMapper
    # Record-specific association requirements. Framework reflection and
    # condition evaluation stay in the mapper; the plugin consumes plain
    # callables and never sees a reflection.
    module AssociationRequirements
      module_function

      # A presence validator only counts when its conditions hold for the
      # record being baked, so a conditional has_one requirement (an unless:
      # guard) is honoured without caching record-specific results on the class.
      def presence_applicable?(klass, reflection, record)
        return false unless klass.respond_to?(:validators_on)

        klass.validators_on(reflection.name).any? do |validator|
          validator.is_a?(ActiveModel::Validations::PresenceValidator) &&
            Conditional.applies?(validator, record, reflection.name.to_s)
        end
      end

      # A scoped has_one loses Rails' automatic inverse detection. Fall back to
      # the belongs_to on the target that shares its foreign key so the child
      # can still be bound back to this owner. Other shapes keep their
      # verified-inverse-only behaviour.
      def inverse(reflection)
        return reflection.inverse_of if reflection.inverse_of
        return nil unless reflection.macro == :has_one
        return nil if reflection.options[:inverse_of] == false

        matching_inverse(reflection)
      rescue StandardError
        nil
      end

      def matching_inverse(reflection)
        key = Array(reflection.foreign_key).map(&:to_s)
        reflection.klass.reflect_on_all_associations(:belongs_to).find do |candidate|
          Array(candidate.foreign_key).map(&:to_s) == key
        end
      end
    end
  end
end
