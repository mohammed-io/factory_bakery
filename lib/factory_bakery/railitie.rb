require 'rails'

module FactoryBakery
  class Railtie < Rails::Railtie
    config.factory_bakery = ActiveSupport::OrderedOptions.new

    initializer "factory_bakery.primary_generator" do

    end
  end
end