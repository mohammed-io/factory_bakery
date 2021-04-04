require 'rails'
require_relative 'ffaker_generator'

module FactoryBakery
  class Railtie < Rails::Railtie
    config.factory_bakery = ActiveSupport::OrderedOptions.new
    config.factory_bakery.generators ||= [FFakerGenerator.new]

    initializer "factory_bakery.generators" do
      FactoryBakery.generators = config.factory_bakery.generators
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