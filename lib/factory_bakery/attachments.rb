# frozen_string_literal: true

require 'factory_bakery'

require_relative 'attachments/fixture'
require_relative 'attachments/fixtures'
require_relative 'attachments/adapters/validation'
require_relative 'attachments/adapters/active_storage'
require_relative 'attachments/adapters/paperclip'
require_relative 'attachments/adapter'
require_relative 'attachments/plugin'

# Requiring this file is the opt-in switch. Registration is idempotent per
# plugin object, so requiring it twice is harmless.
FactoryBakery.register_plugin(FactoryBakery::Attachments::Plugin)
