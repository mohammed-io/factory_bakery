# frozen_string_literal: true

# The suite exercises the gem inside a Rails/ActiveRecord context (it boots
# real Rails applications and defines schema-backed models), so it loads the
# frameworks before the gem: the gem's Rails integration (the Railtie and the
# default mapper) registers only when its framework is already loaded, and the
# framework-agnostic core never loads one on its own.
require 'rails'
require 'active_record'
require 'factory_bakery'
require_relative 'support/database'
require_relative 'support/macros/define_constant'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
