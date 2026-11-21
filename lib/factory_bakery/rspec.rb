# frozen_string_literal: true

require 'factory_bakery'

# Optional RSpec integration: generated data follows RSpec's seed, so
# `rspec --seed N` reproduces the values. Require it from spec/spec_helper.rb
# or spec/rails_helper.rb:
#
#   require 'factory_bakery/rspec'
#
# Without it the seed comes from FACTORY_BAKERY_SEED, FactoryBakery.seed=
# (an Integer or a callable), or a random choice made once per process.
FactoryBakery.register_test_framework_seed(label: 'RSpec', reproduce: 'rspec --seed %d') do
  RSpec.configuration.seed if defined?(RSpec.configuration)
end
