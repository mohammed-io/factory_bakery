# frozen_string_literal: true

require 'ffaker'
require_relative 'factory_bakery/version'
require_relative 'factory_bakery/railitie'
require_relative 'factory_bakery/bakery_builder'

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
    def bake(klass, **overrides)
      BakeryBuilder.new(klass).build(overrides: overrides)
    end

    def bake!(klass, **overrides)
      object = bake(klass, **overrides)
      object.save! if object.respond_to?(:save!)
      object
    end
  end
end
