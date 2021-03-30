# frozen_string_literal: true

require_relative "factory_bakery/version"
require_relative 'factory_bakery/railitie'
require_relative 'factory_bakery/generator_registry'
require_relative 'factory_bakery/ffaker_generator'
require_relative 'factory_bakery/factory_bakery'
require_relative 'factory_bakery/attribute_descriptor'

module FactoryBakery
  class Error < StandardError; end
  # Your code goes here...
end
