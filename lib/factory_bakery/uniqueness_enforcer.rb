# frozen_string_literal: true

module FactoryBakery
  # Makes uniqueness-validated attributes actually unique at bake time.
  #
  # The check is delegated to the mapper (which uses the model's own
  # uniqueness validator), so scoping, case sensitivity, conditions, enum
  # mapping and STI finder resolution behave exactly as they do during a real
  # save. A fresh filler regenerates the value on collision; when the value
  # space is exhausted (for example a single inclusion-forced value already
  # present in the database), a FactoryBakery::Error is raised instead of
  # returning a doomed record.
  class UniquenessEnforcer
    MAX_ATTEMPTS = 10

    def initialize(record, heuristic_attribute_names)
      @record = record
      @heuristic_attribute_names = Array(heuristic_attribute_names)
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
        return unless FactoryBakery::MapperRegistry.uniqueness_check(@record, attribute, value)

        attempts += 1
        raise exhaustion_error(attribute, value) if attempts >= MAX_ATTEMPTS

        assign(attribute, regenerate(attribute))
      end
    end

    def regenerate(attribute)
      filler = AttributeFillers::FillerSelector.cached_for(@record.class, attribute)
      filler.call
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
