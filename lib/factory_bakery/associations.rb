# frozen_string_literal: true

require 'factory_bakery'

require_relative 'associations/configuration'
require_relative 'associations/declaration'
require_relative 'associations/dsl'
require_relative 'associations/required_builder'
require_relative 'associations/plugin'

# Requiring this file is the opt-in switch. Registration is idempotent per
# plugin object, so requiring it twice is harmless.
FactoryBakery.register_plugin(FactoryBakery::Associations::Plugin)
