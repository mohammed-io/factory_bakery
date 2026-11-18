# frozen_string_literal: true

module FactoryBakery
  # Makes uniqueness validatable attributes actually unique at bake time.
  #
  # The check is delegated to the model's own ActiveRecord::UniquenessValidator,
  # so scoping, case sensitivity, conditions, enum mapping and STI finder
  # resolution behave exactly as they do during a real save. A fresh filler
  # regenerates the value on collision; when the value space is exhausted (for
  # example a single inclusion-forced value already present in the database),
  # a FactoryBakery::Error is raised instead of returning a doomed record.
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
      validators = uniqueness_validators_for(attribute)
      return if validators.empty?

      attempts = 0
      loop do
        value = read_value(attribute)
        return unless taken?(validators, attribute, value)

        attempts += 1
        raise exhaustion_error(attribute, value) if attempts >= MAX_ATTEMPTS

        assign(attribute, regenerate(attribute))
      end
    end

    # Use the real validator against a throwaway copy of the record so its
    # errors are not mixed into the object the caller receives.
    def taken?(validators, attribute, value)
      validators.any? do |validator|
        probe = build_probe(attribute, value)
        validator.validate_each(probe, attribute, value)
        taken_error?(probe.errors, attribute)
      end
    end

    # `Errors#added?` does a strict options match, but the uniqueness validator
    # attaches the candidate as `value:`. `details` keeps just the error kind.
    def taken_error?(errors, attribute)
      details = errors.details[attribute.to_sym] || errors.details[attribute.to_s]
      Array(details).any? { |detail| detail[:error] == :taken }
    end

    def build_probe(attribute, value)
      probe = @record.dup
      probe.public_send("#{attribute}=", value) if probe.respond_to?("#{attribute}=")
      probe.errors.clear if probe.respond_to?(:errors)
      probe
    end

    def regenerate(attribute)
      filler = AttributeFillers::FillerSelector.new(@record.class, attribute).call
      filler.call
    end

    def read_value(attribute)
      @record.public_send(attribute)
    end

    def assign(attribute, value)
      setter = "#{attribute}="
      @record.public_send(setter, value) if @record.respond_to?(setter)
    end

    def uniqueness_validators_for(attribute)
      return [] unless active_record_target?
      return [] unless @record.class.respond_to?(:validators_on)

      @record.class.validators_on(attribute).select do |validator|
        validator.is_a?(ActiveRecord::Validations::UniquenessValidator)
      end
    end

    def active_record_target?
      defined?(ActiveRecord::Base) && @record.is_a?(ActiveRecord::Base)
    end

    def exhaustion_error(attribute, value)
      name = "#{@record.class}##{attribute}"
      constraints = all_validators_for(attribute).map { |validator| describe_validator(validator) }.join(', ')

      FactoryBakery::Error.new(
        "could not generate a unique value for #{name}: #{value.inspect} keeps " \
        "colliding after #{MAX_ATTEMPTS} attempts. Constraints: #{constraints}. " \
        'Pass an explicit value with an override or relax the constraint.'
      )
    end

    def all_validators_for(attribute)
      return [] unless @record.class.respond_to?(:validators_on)

      @record.class.validators_on(attribute)
    end

    def describe_validator(validator)
      name = validator.class.name.to_s.split('::').last.to_s.sub(/Validator\z/, '')
      ignored = %i[if unless on class allow_nil allow_blank message]
      options = validator.options.reject { |key, _| ignored.include?(key) }
      options = options.transform_values { |value| value.is_a?(Proc) ? '<callable>' : value }
      options.empty? ? name : "#{name}: #{options.inspect}"
    end
  end
end
