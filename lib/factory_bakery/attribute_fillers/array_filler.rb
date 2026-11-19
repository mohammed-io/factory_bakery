# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    # Fills adapter-native array columns (PostgreSQL `t.string "tags",
    # array: true`) with small Arrays of element-plausible values. A bare
    # String is not usable here: model code reads these columns with Array
    # APIs (Mastodon::CustomFilter#context calls #map on the value).
    #
    # A pure generator: the mapper plugin normalizes the column into a
    # ConstraintSet with type :array and an element-type hint; the core never
    # reads a framework column object. Adapters without an array type map the
    # column to its native type, so this filler is never routed there.
    class ArrayFiller
      include ValueResolution
      include PlausibleStrings

      # Bounded regeneration for exclusion constraints, matching the budget of
      # the other fillers. Exhaustion raises instead of leaking a forbidden
      # value.
      MAX_ATTEMPTS = 10
      MIN_ELEMENTS = 1
      MAX_ELEMENTS = 3

      def initialize(model_class, attr_name)
        @model_class = model_class
        @attr_name = attr_name.to_s
        @constraints = ConstraintSet.for(model_class, @attr_name)
      end

      def call(context = nil)
        return nil if absence_required?

        array_set = resolved_array_set(context)
        attempts = 0
        loop do
          # Each pass builds a genuinely new Array, which is what V1
          # uniqueness regeneration needs when a value collides.
          value = array_set ? array_set.sample : build_candidate(context)
          return value unless forbidden_values?(value, context)

          attempts += 1
          raise exclusion_exhaustion_error if attempts >= MAX_ATTEMPTS
        end
      end

      private

      # An inclusion set whose members are arrays constrains the whole value,
      # so sample one of those arrays. Such sets are rare; scalar sets are
      # handled as an element pool in #string_element (documented there).
      def resolved_array_set(context)
        return nil unless allowed_values?

        values = resolve_set(@constraints.allowed_values, context, 'inclusion')
        return nil unless values.is_a?(Array) && values.any? { |value| value.is_a?(Array) }

        values.select { |value| value.is_a?(Array) }
      end

      def build_candidate(context)
        Array.new(rand(MIN_ELEMENTS..MAX_ELEMENTS)) { element(context) }
      end

      def element(context)
        case @constraints.array_element_type
        when :integer then rand(1..100)
        when :float then rand * 100
        when :boolean then [true, false].sample
        else string_element(context)
        end
      end

      # String elements use the same name-pattern logic as a scalar string
      # column. A scalar inclusion set is used as the element pool so the
      # generated value stays array-shaped; a validator that compares the
      # whole array against scalar members cannot be satisfied by any filler
      # and should be expressed with an explicit factory definition.
      def string_element(context)
        pool = scalar_inclusion_set(context)
        return pool.sample unless pool.empty?

        generate_by_pattern
      end

      def scalar_inclusion_set(context)
        return [] unless allowed_values?

        values = resolve_set(@constraints.allowed_values, context, 'inclusion')
        return [] unless values.is_a?(Array)

        values.select { |value| element_type_compatible?(value) }
      end

      def element_type_compatible?(value)
        case @constraints.array_element_type
        when :integer then value.is_a?(Integer)
        when :float then value.is_a?(Numeric)
        when :boolean then [true, false].include?(value)
        else value.is_a?(String)
        end
      end

      def exclusion_exhaustion_error
        FactoryBakery::Error.new(
          "could not generate a value for #{@model_class}##{@attr_name} that satisfies " \
          "exclusion after #{MAX_ATTEMPTS} attempts: #{@constraints.forbidden_values.inspect}. " \
          'Pass an explicit value with an override or relax the constraint.'
        )
      end
    end
  end
end
