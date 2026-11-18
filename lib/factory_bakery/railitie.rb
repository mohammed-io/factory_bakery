# frozen_string_literal: true

require 'rails'

module FactoryBakery
  class Railtie < Rails::Railtie
    config.factory_bakery = ActiveSupport::OrderedOptions.new

    config.after_initialize do |app|
    end
  end
end
