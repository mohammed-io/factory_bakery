# frozen_string_literal: true

module FactoryBakery
  class BakeryBuilder
    class BuildingInProgress < StandardError; end

    def initialize(model_klass, builder_proc)
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

    def evaluate_builder
      instance_eval(&@builder_proc)
      # Reset the methods to be called,
      # because this call should not do any method calls on the instance
      # Only evaluate the existing traits and if there's an error ahead of time.
      @methods_to_be_called_on_object = []
    end

    def build(trait: nil)
      evaluate_builder
      raise BuildingInProgress if @build_is_in_progress

      # Prevent recursive calls to build method.
      @build_is_in_progress = true

      instance_eval(&@builder_proc)

      # Trait eval must be called after the top level block,
      # this is where the trait is registered.
      instance_eval(&@traits.fetch(trait)) if trait.present?

      # Should be instantiated after the builder_proc is evaluated
      # Because this is where @initialize_with_attributes variabe is set
      object = if @initialize_with_attributes
                 @model_klass.new(@initialize_with_attributes)
               else
                 @model_klass.new
               end

      @methods_to_be_called_on_object.each do |method_name, block|
        object.public_send("#{method_name}=", block.call)
      end

      object
    ensure
      @build_is_in_progress = false
    end

    def method_missing(method_name, *, &block)
      # Add methods to be called later, because we would like to
      # prioritize calling this class methods such as `initialize_with`.
      @methods_to_be_called_on_object << [method_name, block]
    end
  end
end
