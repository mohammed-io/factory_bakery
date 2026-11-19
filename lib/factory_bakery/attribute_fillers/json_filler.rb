# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    # Fills json/jsonb columns with shallow, JSON-serializable Hashes.
    #
    # A generic String is not a usable value for a column that applications
    # validate as a Hash (Discourse's AppearanceChange calls #keys on its
    # site_settings jsonb column). On a real JSON column a non-JSON String is
    # also cast to nil, so the value is lost on reload. Every generated Hash
    # uses string keys and JSON primitives only: JSON canonicalizes object keys
    # to strings, so this keeps the bake!/reload round trip lossless on every
    # adapter that exposes the type.
    class JsonFiller
      include ValueResolution

      # Bounded regeneration for exclusion constraints, matching the budget of
      # the other fillers. Exhaustion raises instead of leaking a forbidden
      # value.
      MAX_ATTEMPTS = 10

      # A pure generator: the constraints arrive already normalized in a
      # ConstraintSet, resolved from the target once at construction.
      def initialize(model_class, attr_name)
        @model_class = model_class
        @attr_name = attr_name.to_s
        @constraints = ConstraintSet.for(model_class, @attr_name)
      end

      def call(context = nil)
        return nil if absence_required?

        attempts = 0
        loop do
          value = allowed_values? ? pick_from(@constraints.allowed_values, context) : build_candidate
          return value unless forbidden_values?(value, context)

          attempts += 1
          raise exclusion_exhaustion_error if attempts >= MAX_ATTEMPTS
        end
      end

      private

      # One random seed drives the whole structure. Every value stays JSON-
      # serializable, and each regeneration produces a genuinely new Hash,
      # which is what V1 uniqueness needs when a payload collides.
      def build_candidate
        seed = FFaker::Lorem.word
        {
          'name' => seed,
          'count' => seed.length,
          'enabled' => seed.length.even?,
          'weight' => seed.length / 2.0,
          'tags' => [seed, seed.reverse],
          'details' => { 'label' => seed.capitalize, 'rank' => seed.length }
        }
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
