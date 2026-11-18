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

    class << self
      attr_reader :definitions
    end

    def self.for(model_klass, &blk)
      instance = new(model_klass, blk)
      @definitions[model_klass] = instance
      instance
    end

    def initialize_with(attributes)
      @initialize_with_attributes = attributes
    end

    def trait(trait_name, &blk)
      @traits[trait_name] = blk
    end

    def build(overrides: {}, trait: nil)
      evaluate_builder
      raise BuildingInProgress if @build_is_in_progress

      # Prevent recursive calls to build method.
      @build_is_in_progress = true

      # Evaluate declarations again so their blocks run fresh on every build.
      # Trait evaluation follows the top-level block so registered traits are available.
      evaluate_builder_proc(trait)

      object = instantiate
      apply_values(object, resolved_values(overrides), explicit_names(overrides))
      object
    ensure
      @build_is_in_progress = false
    end

    def method_missing(method_name, *, &block)
      # Add methods to be called later, because we would like to
      # prioritize calling this class methods such as `initialize_with`.
      @methods_to_be_called_on_object << [method_name, block]
    end

    private

    def evaluate_builder
      return unless @builder_proc

      instance_eval(&@builder_proc)
      # Reset the methods to be called, because this pass should not apply any
      # declarations. It only registers traits and initialize_with.
      @methods_to_be_called_on_object = []
    end

    def evaluate_builder_proc(trait)
      return unless @builder_proc

      instance_eval(&@builder_proc)
      instance_eval(&@traits.fetch(trait)) if trait && @traits.key?(trait)
    end

    def instantiate
      if @initialize_with_attributes
        @model_klass.new(@initialize_with_attributes)
      else
        @model_klass.new
      end
    end

    # Precedence: heuristics < declarations < call-site overrides.
    def resolved_values(overrides)
      heuristic_values
        .merge(declared_values)
        .merge(normalize_keys(overrides))
    end

    def explicit_names(overrides)
      declared_names + normalize_keys(overrides).keys
    end

    def heuristic_values
      return {} unless @model_klass.respond_to?(:columns_hash)

      skip = declared_names + normalize_keys(@initialize_with_attributes).keys

      @model_klass.columns_hash.each_key.with_object({}) do |column_name, values|
        next if column_name.to_s == @model_klass.primary_key.to_s
        next if skip.include?(column_name.to_s)

        filler = AttributeFillers::FillerSelector.new(@model_klass, column_name).call
        next if filler.is_a?(AttributeFillers::NoopFiller)
        next if filler.is_a?(AttributeFillers::ConfirmationFiller)

        values[column_name.to_s] = filler.call
      end
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
      return unless @model_klass.respond_to?(:columns_hash)

      @model_klass.columns_hash.each_key do |column_name|
        next if reserved.include?(column_name.to_s)

        filler = AttributeFillers::FillerSelector.new(@model_klass, column_name).call
        next unless filler.is_a?(AttributeFillers::ConfirmationFiller)

        source_name = column_name.to_s.sub(/_confirmation$/, '')
        source_value = object.public_send(source_name) if object.respond_to?(source_name)
        object.public_send("#{column_name}=", source_value)
      end
    end

    def normalize_keys(hash)
      (hash || {}).transform_keys(&:to_s)
    end
  end
end
