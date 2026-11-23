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
  # A fresh filler regenerates the value on collision; when the value space is
  # exhausted (for example a single inclusion-forced value already present in
  # the database), a FactoryBakery::Error is raised instead of returning a
  # doomed record.
  class UniquenessEnforcer
    MAX_ATTEMPTS = 10

    # Regenerating normally produces a fresh value. When a filler keeps
    # repeating itself -- a short bare word is all a uniqueness-validated string
    # column gets -- regeneration alone cannot make progress and the attempt
    # budget runs out, so from this collision on the candidate is given an
    # entropy suffix. The first two collisions stay plain to keep the ordinary
    # regenerate-on-collision values.
    ENTROPY_AFTER_ATTEMPTS = 3

    # Four random bytes as hex: eight characters behind a dash, drawn from the seeded generator.
    ENTROPY_HEX_BYTES = 4

    # `defer_to_save` lets a `bake!` root leave the database check of a value
    # to the save that follows (see #taken_in_database?). Only the caller that
    # knows no `valid?` will run before that save may ask for it: a `valid?`
    # would read the still-unchecked collision as an invalid record.
    def initialize(record, heuristic_attribute_names, defer_to_save: false)
      @record = record
      @heuristic_attribute_names = Array(heuristic_attribute_names)
      @defer_to_save = defer_to_save
    end

    def call
      @heuristic_attribute_names.each { |attribute| enforce(attribute) }
    end

    private

    def enforce(attribute)
      return unless FactoryBakery::MapperRegistry.uniqueness_validated?(@record.class, attribute)

      attempts = 0
      loop do
        value = read_value(attribute)
        return accept(attribute, value) unless collision?(attribute, value)

        attempts += 1
        raise exhaustion_error(attribute, value) if attempts >= MAX_ATTEMPTS

        assign(attribute, candidate(attribute, attempts))
      end
    end

    # Taken in this bake's graph, or taken in the database.
    def collision?(attribute, value)
      taken_in_graph?(attribute, value) || taken_in_database?(attribute, value)
    end

    def taken_in_graph?(attribute, value)
      FactoryBakery::BuildContext.unique_value_taken?(registry_key(attribute, value))
    end

    # The root record of a `bake!` is saved by that same call, and a uniqueness
    # validator checks it again then. Asking the database now as well would
    # run the same query twice, so the value is left to the save, and
    # UniquenessRetry regenerates it if the save finds it taken.
    def taken_in_database?(attribute, value)
      return false if deferred_to_save?(attribute)

      FactoryBakery::MapperRegistry.uniqueness_check(@record, attribute, value)
    end

    def deferred_to_save?(attribute)
      @defer_to_save && FactoryBakery::BuildContext.persist_root? &&
        FactoryBakery::MapperRegistry.save_validates_uniqueness?(@record.class, attribute)
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
      [table_identity, attribute.to_s, normalize(attribute, value)]
    end

    def table_identity
      klass = @record.class
      klass.respond_to?(:table_name) ? klass.table_name : klass
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

      suffix = entropy_suffix
      return value unless suffix_allowed?(attribute, value, suffix)

      value + suffix
    end

    def entropy_suffix
      "-#{FactoryBakery::Randomness.hex(ENTROPY_HEX_BYTES)}"
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
