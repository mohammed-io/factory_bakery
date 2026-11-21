# frozen_string_literal: true

require 'factory_bakery'

# Optional Minitest integration: generated data follows Minitest's seed, so
# `bin/rails test --seed N` reproduces the values. Require it from
# test/test_helper.rb:
#
#   require 'factory_bakery/minitest'
#
# Without it the seed comes from FACTORY_BAKERY_SEED, FactoryBakery.seed=
# (an Integer or a callable), or a random choice made once per process.
FactoryBakery.register_test_framework_seed(label: 'Minitest', reproduce: 'bin/rails test --seed %d') do
  Minitest.seed if defined?(Minitest.seed)
end
