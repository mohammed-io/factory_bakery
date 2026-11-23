# frozen_string_literal: true

module FactoryBakery
  # What a built record's generated values were: the attribute names the gem
  # filled, the seed in force and the top-level bake that produced it. It is
  # kept as an instance variable on the record, not as an attribute, so it is
  # never persisted and never shows up in attribute reads.
  module Provenance
    IVAR = :@factory_bakery_provenance
    Origin = Data.define(:filled, :seed, :model, :ordinal)

    class << self
      def record(object, filled_names)
        return if object.frozen?

        scope = Randomness.scope
        origin = Origin.new(
          filled: filled_names.map(&:to_s), seed: Seed.current, model: scope&.model, ordinal: scope&.ordinal
        )
        object.instance_variable_set(IVAR, origin)
      end

      def of(object)
        object.instance_variable_get(IVAR)
      end

      # A fill that was undone (reset to its column default) is no longer a
      # generated value of the record.
      def forget(object, name)
        origin = of(object)
        return unless origin

        object.instance_variable_set(IVAR, origin.with(filled: origin.filled - [name.to_s]))
      end
    end
  end
end
