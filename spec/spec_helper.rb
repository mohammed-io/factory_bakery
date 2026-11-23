# frozen_string_literal: true

# Coverage must be started before the gem loads. Only the regex generator is
# measured and gated: every file under lib/factory_bakery/regex_generation/
# (and its entry file) needs 100% line and branch coverage, and the run fails
# otherwise. The rest of the gem has no coverage minimum. A partial run
# (a single spec file) cannot reach 100%; set SKIP_REGEX_COVERAGE_GATE=1 for those.
require 'simplecov'

SimpleCov.start do
  enable_coverage :branch
  skip { |source_file| !source_file.filename.include?('/lib/factory_bakery/regex_generation') }
  unless ENV['SKIP_REGEX_COVERAGE_GATE']
    coverage(:line) { minimum 100, per: :file }
    coverage(:branch) { minimum 100, per: :file }
  end
end

# The suite exercises the gem inside a Rails/ActiveRecord context (it boots
# real Rails applications and defines schema-backed models), so it loads the
# frameworks before the gem: the gem's Rails integration (the Railtie and the
# default mapper) registers only when its framework is already loaded, and the
# framework-agnostic core never loads one on its own.
require 'rails'
require 'active_record'
require 'factory_bakery'
require 'logger'
require_relative 'support/database'
require_relative 'support/macros/define_constant'

# The seed announcement is a process-level log line. The suite checks it in
# seed_spec.rb through its own logger, so the default stderr output stays quiet.
FactoryBakery.logger = Logger.new(nil)

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  # Savepoints are off by default (like factory_bot), so every example runs
  # that way unless it is about rolling back what a failed bake wrote: those
  # say `:savepoints` and run with the setting on.
  config.around(:each, :savepoints) do |example|
    FactoryBakery.savepoints = true
    example.run
  ensure
    FactoryBakery.savepoints = false
  end
end
