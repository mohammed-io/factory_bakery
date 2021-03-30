require 'rails'
require_relative 'ffaker_generator'

module FactoryBakery
  class Railtie < Rails::Railtie
    config.factory_bakery = ActiveSupport::OrderedOptions.new
    config.factory_bakery.first_generator = FFakerGenerator.new

    initializer "factory_bakery.first_generator" do
      FactoryBakery.first_generator = config.factory_bakery.first_generator
    end

    initializer "factory_bakery.second_generator" do
      FactoryBakery.second_generator = config.factory_bakery.second_generator
    end

    config.after_initialize do |app|
      #
    end
  end
end

# Introduce global functions, good idea?
def bake(model, custom_values = {}, &block)
  FactoryBakery::FactoryBakery.instance.bake(model, custom_values, &block)
end

def bake!(model, custom_values = {}, &block)
  FactoryBakery::FactoryBakery.instance.bake!(model, custom_values, &block)
end