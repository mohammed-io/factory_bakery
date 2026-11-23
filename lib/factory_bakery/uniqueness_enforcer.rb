# frozen_string_literal: true

module FactoryBakery
  # Makes uniqueness-validated attributes actually unique at bake time.
  #
  # Two sources are consulted. The mapper asks the database through the
  # model's own uniqueness validator, so scoping, case sensitivity, conditions,
  # enum mapping and STI finder resolution behave exactly as they do during a
  # real save. BuildContext answers whether an unsaved sibling generated
  # earlier in the same top-level bake already took the value -- two parents of
  # different edges are invisible to the database until the root save, and
  # without that check the second INSERT fails.
  #
  # A fresh filler regenerates the value on collision; an exhausted value
  # space raises a FactoryBakery::Error instead of returning a doomed record.
  class UniquenessEnforcer
    MAX_ATTEMPTS = 10

    # Regenerating normally produces a fresh value. When a filler keeps
    # repeating itself -- a short bare word is all a uniqueness-validated string
    # column gets -- regeneration alone cannot make progress, so from this
    # collision on the candidate is given an entropy suffix. The first two
    # collisions stay plain to keep the ordinary regenerate-on-collision values.
    ENTROPY_AFTER_ATTEMPTS = 3

    # Four random bytes as hex: eight characters behind a dash, drawn from the seeded generator.
    ENTROPY_HEX_BYTES = 4

    def initialize(record, heuristic_attribute_names)
      @record = record
      @heuristic_attribute_names = Array(heuristic_attribute_names)
    end

    def call
      answered = batch_answers
      @heuristic_attribute_names.each { |attribute| enforce(attribute, answered[attribute.to_s]) }
    end

    private

    # One statement for the unique columns whose value this bake's graph does
    # not already hold; the rest are asked one by one by `enforce`.
    def batch_answers
      pending = @heuristic_attribute_names.filter_map do |attribute|
        next unless FactoryBakery::MapperRegistry.uniqueness_validated?(@record.class, attribute)

        value = read_value(attribute)
        next if taken_in_graph?(attribute, value)

        [attribute.to_s, value]
      end.to_h
      return {} if pending.empty?

      FactoryBakery::MapperRegistry.uniqueness_taken_many(@record, pending)
    end

    def enforce(attribute, known_taken = nil)
      return unless FactoryBakery::MapperRegistry.uniqueness_validated?(@record.class, attribute)

      attempts = 0
      loop do
        value = read_value(attribute)
        return accept(attribute, value) unless collision?(attribute, value, known_taken, attempts.positive?)

        attempts += 1
        raise exhaustion_error(attribute, value) if attempts >= MAX_ATTEMPTS

        assign(attribute, candidate(attribute, attempts))
      end
    end

    # Taken in this bake's graph, or taken in the database. The first pass of
    # a batched attribute reuses the answer the batched check already fetched;
    # after a regeneration the database is asked again.
    def collision?(attribute, value, known_taken, regenerated)
      return true if taken_in_graph?(attribute, value)
      return taken_in_database?(attribute, value) if regenerated || known_taken.nil?

      known_taken
    end

    def taken_in_graph?(attribute, value)
      FactoryBakery::BuildContext.unique_value_taken?(registry_key(attribute, value))
    end

    def taken_in_database?(attribute, value)
      FactoryBakery::MapperRegistry.uniqueness_check(@record, attribute, value)
    end

    # An accepted value is remembered for the rest of this bake, so a sibling
    # built later by another edge cannot reuse it.
    def accept(attribute, value)
      FactoryBakery::BuildContext.record_unique_value(registry_key(attribute, value))
      value
    end

    # Table identity (so an STI subclass shares its parent's column), attribute
    # and normalized value: two unsaved records collide exactly when the
    # database would see one value in one column.
    def registry_key(attribute, value)
      klass = @record.class
      [klass.respond_to?(:table_name) ? klass.table_name : klass, attribute.to_s, normalize(attribute, value)]
    end

    # A `case_sensitive: false` uniqueness validator folds case, so the
    # registry must too: "Token" and "token" collide for it.
    def normalize(attribute, value)
      return value unless value.is_a?(String)
      return value unless FactoryBakery::MapperRegistry.uniqueness_case_insensitive?(@record.class, attribute)

      value.downcase
    end

    def regenerate(attribute)
      filler = AttributeFillers::FillerSelector.cached_for(@record.class, attribute)
      filler.call
    end

    # A fresh value from the same filler, with an entropy suffix once a
    # repeating filler is the likelier cause of the collision.
    def candidate(attribute, attempts)
      value = regenerate(attribute)
      return value if attempts < ENTROPY_AFTER_ATTEMPTS

      suffix = "-#{FactoryBakery::Randomness.hex(ENTROPY_HEX_BYTES)}"
      return value unless suffix_allowed?(attribute, value, suffix)

      value + suffix
    end

    # The suffix is only safe for a free-form string: a declared shape would
    # reject it outright, and a length cap must have room for it.
    def suffix_allowed?(attribute, value, suffix)
      return false unless value.is_a?(String)

      constraints = FactoryBakery::MapperRegistry.constraints_for(@record.class, attribute)
      return false if constrained_shape?(constraints)

      suffix_fits?(constraints, value, suffix)
    end

    # A declared format, an inclusion list, an enum, a numericality rule or an
    # exact length all reject a value that merely looks like the filler's.
    def constrained_shape?(constraints)
      constraints.format_validated || constraints.inclusion_validated ||
        constraints.enum_attribute || constraints.numericality_validated ||
        constraints.exact_length
    end

    def suffix_fits?(constraints, value, suffix)
      limit = [constraints.max_length, constraints.db_limit].select { |bound| bound.is_a?(Integer) }.min
      limit.nil? || value.length + suffix.length <= limit
    end

    def read_value(attribute)
      @record.public_send(attribute)
    end

    def assign(attribute, value)
      setter = "#{attribute}="
      @record.public_send(setter, value) if @record.respond_to?(setter)
    end

    def exhaustion_error(attribute, value)
      name = "#{@record.class}##{attribute}"
      constraints = FactoryBakery::MapperRegistry.validator_descriptions(@record.class, attribute).join(', ')

      FactoryBakery::Error.new(
        "could not generate a unique value for #{name}: #{value.inspect} keeps " \
        "colliding after #{MAX_ATTEMPTS} attempts. Constraints: #{constraints}. " \
        'Pass an explicit value with an override or relax the constraint.'
      )
    end
  end
end
