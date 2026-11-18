# frozen_string_literal: true

require 'ffaker'
require_relative 'factory_bakery/version'
require_relative 'factory_bakery/railitie'
require_relative 'factory_bakery/bakery_builder'
require_relative 'factory_bakery/counter_cache_detector'
require_relative 'factory_bakery/definition_loader'
require_relative 'factory_bakery/methods'

# Attribute fillers
require_relative 'factory_bakery/attribute_fillers/common_validators'
require_relative 'factory_bakery/attribute_fillers/noop_filler'
require_relative 'factory_bakery/attribute_fillers/string_filler'
require_relative 'factory_bakery/attribute_fillers/integer_filler'
require_relative 'factory_bakery/attribute_fillers/float_filler'
require_relative 'factory_bakery/attribute_fillers/boolean_filler'
require_relative 'factory_bakery/attribute_fillers/date_filler'
require_relative 'factory_bakery/attribute_fillers/datetime_filler'
require_relative 'factory_bakery/attribute_fillers/enum_filler'
require_relative 'factory_bakery/attribute_fillers/acceptance_filler'
require_relative 'factory_bakery/attribute_fillers/confirmation_filler'
require_relative 'factory_bakery/attribute_fillers/filler_selector'

module FactoryBakery
  class Error < StandardError; end

  class << self
    attr_writer :definition_paths

    # No paths are configured until the host app (or the Railtie) sets them.
    def definition_paths
      @definition_paths ||= []
    end

    def find_definitions
      DefinitionLoader.call(definition_paths)
    end

    def define(target, klass: nil, &block)
      BakeryBuilder.register(target, klass: klass, &block)
    end

    def bake(target, *traits, **overrides)
      model_klass, definition = BakeryBuilder.resolve(target)
      BakeryBuilder.new(model_klass, definition).build(overrides: overrides, traits: traits)
    end

    def bake!(target, *traits, **overrides)
      object = bake(target, *traits, **overrides)
      object.save! if object.respond_to?(:save!)
      object
    end
  end
end
