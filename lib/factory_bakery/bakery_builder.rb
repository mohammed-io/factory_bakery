# frozen_string_literal: true

module FactoryBakery
  class BakeryBuilder
    class BuildingInProgress < StandardError; end

    def initialize(model_klass, builder_proc = nil)
      @model_klass = model_klass
      @builder_proc = builder_proc

      @methods_to_be_called_on_object = []
      @traits = {}
    end

    @definitions = {}

    # A registered factory: its declaration block and the class explicitly
    # bound to it when declared with `klass:`.
    Definition = Struct.new(:builder_proc, :klass)

    class << self
      attr_reader :definitions

      # Registers a definition under a class or a symbol name. Class and symbol
      # keys are independent, and re-registering a key overwrites it so
      # definition files can be reloaded safely.
      def register(target, klass: nil, &blk)
        definitions[target] = Definition.new(blk, klass)
      end

      # Normalizes a bake target into the class to instantiate and the
      # declaration block to apply. Classes bake with or without registration;
      # symbols must be registered and never fall back to constantization here.
      def resolve(target)
        case target
        when Class
          [target, definitions[target]&.builder_proc]
        when Symbol
          definition = definitions[target]
          raise FactoryBakery::Error, "No factory is registered for #{target.inspect}" unless definition

          [definition.klass || constantize(target), definition.builder_proc]
        else
          raise FactoryBakery::Error,
                "Unsupported bake target #{target.inspect}; pass a class or a registered symbol"
        end
      end

      private

      # Resolves :admin_user to AdminUser without eval. Called at bake time so
      # definition files can load before the model constants they name exist.
      # A missing constant is only ever reported as a clear error naming the
      # symbol; failures are not cached so a later bake can succeed.
      def constantize(symbol)
        name = symbol.to_s.split('_').map(&:capitalize).join
        Object.const_get(name)
      rescue NameError
        raise FactoryBakery::Error,
              "Could not resolve a class for factory #{symbol.inspect} (tried #{name.inspect}); pass klass: when defining it"
      end
    end

    def initialize_with(attributes)
      @initialize_with_attributes = attributes
    end

    def trait(trait_name, &blk)
      @traits[trait_name] = blk
    end

    def build(overrides: {}, traits: [])
      raise BuildingInProgress if @build_is_in_progress

      # Prevent recursive calls to build method.
      @build_is_in_progress = true

      evaluate_declarations(traits)

      object = instantiate
      apply_values(object, resolved_values(overrides), explicit_names(overrides))
      object
    ensure
      @build_is_in_progress = false
    end

    def method_missing(method_name, *, &block)
      # Defer attribute blocks so they run once per build, after the whole
      # definition block has registered traits and initialize_with.
      @methods_to_be_called_on_object << [method_name, block]
    end

    private

    def evaluate_declarations(traits)
      @methods_to_be_called_on_object = []
      instance_eval(&@builder_proc) if @builder_proc

      # Traits are appended after the base declarations and applied in the
      # order requested, so later assignments win for duplicate attributes.
      traits.each do |name|
        unless @traits.key?(name)
          raise FactoryBakery::Error, "Trait #{name.inspect} is not declared for #{@model_klass}"
        end

        instance_eval(&@traits[name])
      end
    end

    def instantiate
      return @model_klass.new unless @initialize_with_attributes

      parameters = @model_klass.instance_method(:initialize).parameters
      return build_with_setters if parameters.empty?
      return @model_klass.new(**symbolized_initialize_with) if keyword_initializer?(parameters)

      @model_klass.new(@initialize_with_attributes)
    end

    def keyword_initializer?(parameters)
      parameters.all? { |type, _| %i[key keyreq keyrest].include?(type) }
    end

    def symbolized_initialize_with
      @initialize_with_attributes.each_with_object({}) do |(name, value), attributes|
        attributes[name.to_sym] = value
      end
    end

    # POROs whose constructor takes no arguments receive their initialize_with
    # values through setters, just like declared attributes.
    def build_with_setters
      object = @model_klass.new
      normalize_keys(@initialize_with_attributes).each do |name, value|
        setter = "#{name}="
        object.public_send(setter, value) if object.respond_to?(setter)
      end
      object
    end

    # Precedence: heuristics < declarations (base, then traits) < call-site overrides.
    def resolved_values(overrides)
      heuristic_values
        .merge(declared_values)
        .merge(normalize_keys(overrides))
    end

    def explicit_names(overrides)
      declared_names + normalize_keys(overrides).keys
    end

    def heuristic_values
      skip = declared_names + normalize_keys(@initialize_with_attributes).keys

      candidate_attribute_names.each_with_object({}) do |attribute_name, values|
        next if column_backed? && attribute_name == @model_klass.primary_key.to_s
        next if skip.include?(attribute_name)

        filler = AttributeFillers::FillerSelector.new(@model_klass, attribute_name).call
        next if heuristic_skip?(filler)

        values[attribute_name] = filler.call
      end
    end

    def heuristic_skip?(filler)
      filler.is_a?(AttributeFillers::NoopFiller) ||
        filler.is_a?(AttributeFillers::ConfirmationFiller)
    end

    def column_backed?
      @model_klass.respond_to?(:columns_hash)
    end

    # ActiveRecord targets enumerate their columns. POROs have no schema, so
    # the only attributes that can carry heuristic information are the ones
    # their validators declare.
    def candidate_attribute_names
      return @model_klass.columns_hash.keys.map(&:to_s) if column_backed?

      validator_attribute_names
    end

    def validator_attribute_names
      return [] unless @model_klass.respond_to?(:validators)

      @model_klass.validators.flat_map do |validator|
        names = Array(validator.attributes).map(&:to_s)
        class_name = validator.class.name
        if class_name == 'ActiveModel::Validations::ConfirmationValidator'
          names + names.map { |name| "#{name}_confirmation" }
        else
          names
        end
      end.uniq
    end

    def declared_values
      @methods_to_be_called_on_object.each_with_object({}) do |(name, block), values|
        values[name.to_s] = block.call if block
      end
    end

    def declared_names
      @methods_to_be_called_on_object.map { |name, _| name.to_s }
    end

    def apply_values(object, values, reserved)
      values.each do |name, value|
        setter = "#{name}="
        object.public_send(setter, value) if object.respond_to?(setter)
      end

      apply_confirmations(object, reserved)
    end

    def apply_confirmations(object, reserved)
      candidate_attribute_names.each do |attribute_name|
        next if reserved.include?(attribute_name)

        filler = AttributeFillers::FillerSelector.new(@model_klass, attribute_name).call
        next unless filler.is_a?(AttributeFillers::ConfirmationFiller)

        source_name = attribute_name.sub(/_confirmation$/, '')
        source_value = object.public_send(source_name) if object.respond_to?(source_name)
        setter = "#{attribute_name}="
        object.public_send(setter, source_value) if object.respond_to?(setter)
      end
    end

    def normalize_keys(hash)
      (hash || {}).transform_keys(&:to_s)
    end
  end
end
