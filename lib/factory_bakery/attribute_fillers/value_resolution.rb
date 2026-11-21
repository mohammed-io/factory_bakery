# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    # Bake-time resolution of the raw option forms carried in a ConstraintSet.
    #
    # Mappers keep inclusion/exclusion sets and comparison bounds exactly as
    # the source framework expressed them: literals, Procs and Symbols (which
    # reference other attributes). This module resolves those forms against
    # the object being built when a value is generated, fresh for every bake.
    # An unresolved reference becomes nil, so no NameError or NoMethodError
    # ever escapes a bake.
    module ValueResolution
      # Samples one value from an allowed/forbidden set in its raw form.
      def pick_from(values, context = nil)
        case values
        when Array
          Randomness.sample(values)
        when Range
          Randomness.sample(values.to_a)
        when Proc, Symbol
          pick_from(resolve_set(values, context, 'inclusion'), context)
        else
          values
        end
      end

      def absence_required?
        @constraints.absence_required
      end

      def must_be_present?
        @constraints.must_be_present
      end

      def allowed_values?
        !@constraints.allowed_values.nil?
      end

      def forbidden_values?(value, context = nil)
        forbidden_values = @constraints.forbidden_values
        return false if forbidden_values.nil?

        forbidden = resolve_set(forbidden_values, context, 'exclusion')
        forbidden.respond_to?(:include?) && forbidden.include?(value)
      end

      # The framework accepts a Proc (or a Symbol referencing another
      # attribute) as an inclusion/exclusion set. Resolve it only when a value
      # is generated, fresh for every bake, and pass the object being built to
      # record-aware procs. Literal arrays and ranges stay untouched on the
      # fast path.
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

      # Comparison/numericality options accept literals, Procs and Symbols
      # (cross-attribute references). Resolve them at bake time, against the
      # object being built when one is available. An unresolved reference
      # becomes nil, so no NoMethodError escapes a bake.
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

      # Length validator options (`:minimum`, `:maximum`, `:is`) take the same
      # literal/Proc/Symbol forms as comparison bounds. Resolve them at bake
      # time through the same path. A proc touching a constant that is not
      # loaded yet would otherwise escape as a raw NameError; report it
      # against the model and attribute, with the original error as cause.
      def resolve_length_option(option, context, kind)
        resolve_option_value(option, context)
      rescue FactoryBakery::Error
        raise
      rescue StandardError => e
        raise FactoryBakery::Error,
              "#{@model_class}##{@attr_name}: length :#{kind} #{option.inspect} " \
              "raised #{e.class}: #{e.message}; define referenced constants " \
              'before baking or use a literal integer'
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
    end
  end
end
