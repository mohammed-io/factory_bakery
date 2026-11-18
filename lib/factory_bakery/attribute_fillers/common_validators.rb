# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    module CommonValidators
      attr_reader :allowed_values, :forbidden_values,
                  :absence_required, :must_be_present

      def apply_common_validator(validator)
        case validator.class.name
        when 'ActiveModel::Validations::InclusionValidator'
          # Keep the raw Rails option form. A Proc (or Symbol) is a lazy set:
          # wrapping it with Array() here would sample the Proc itself and
          # stringify it instead of evaluating it at value-generation time.
          @allowed_values = validator.options[:in]
          true
        when 'ActiveModel::Validations::ExclusionValidator'
          @forbidden_values = validator.options[:in]
          true
        when 'ActiveModel::Validations::PresenceValidator', 'ActiveRecord::Validations::PresenceValidator'
          @must_be_present = true
          true
        when 'ActiveModel::Validations::AbsenceValidator', 'ActiveRecord::Validations::AbsenceValidator'
          @absence_required = true
          true
        else
          false
        end
      end

      def pick_from(values, context = nil)
        case values
        when Array
          values.sample
        when Range
          values.to_a.sample
        when Proc, Symbol
          pick_from(resolve_set(values, context, 'inclusion'), context)
        else
          values
        end
      end

      def absence_required?
        @absence_required == true
      end

      def must_be_present?
        @must_be_present == true
      end

      def allowed_values?
        !@allowed_values.nil?
      end

      def forbidden_values?(value, context = nil)
        return false if @forbidden_values.nil?

        forbidden = resolve_set(@forbidden_values, context, 'exclusion')
        forbidden.respond_to?(:include?) && forbidden.include?(value)
      end

      # Rails accepts a Proc (or a Symbol referencing another attribute) as an
      # inclusion/exclusion set. Resolve it only when a value is generated,
      # fresh for every bake, and pass the object being built to record-aware
      # procs. Literal arrays and ranges stay untouched on the fast path.
      def resolve_set(option, context, kind)
        case option
        when Proc
          Array(call_set_proc(option, context, kind))
        when Symbol
          Array(context&.value_for(option))
        else
          option
        end
      end

      # A proc touching not-yet-loaded application constants used to raise a
      # raw NameError from inside filler setup. Report it against the model and
      # attribute that triggered it instead, with the original error as cause.
      def call_set_proc(option, context, kind)
        call_option_proc(option, context)
      rescue StandardError => e
        raise FactoryBakery::Error,
              "#{@model_class}##{@attr_name}: #{kind} :in proc raised " \
              "#{e.class}: #{e.message}; define referenced constants before " \
              'baking or use a literal array/range'
      end

      # Rails comparison/numericality options accept literals, Procs and
      # Symbols (cross-attribute references). Resolve them at bake time,
      # against the object being built when one is available. An unresolved
      # reference becomes nil, so no NoMethodError escapes a bake.
      def resolve_option_value(option, context)
        case option
        when Symbol
          context&.value_for(option)
        when Proc
          resolve_option_value(call_option_proc(option, context), context)
        else
          option
        end
      end

      def call_option_proc(option, context)
        return option.call if option.arity.zero?

        option.call(context&.object)
      end

      # Resolve a Range option whose endpoints may themselves be Procs or
      # Symbols. Beginless/endless ranges and unresolved endpoints are ignored
      # so the filler falls back to its ordinary bound generation.
      def resolve_range(range, context)
        return nil unless range.is_a?(Range)

        first = resolve_option_value(range.begin, context)
        last = resolve_option_value(range.end, context)
        return nil if first.nil? || last.nil?

        range.exclude_end? ? (first...last) : (first..last)
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
