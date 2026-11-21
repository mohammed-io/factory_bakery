# frozen_string_literal: true

module FactoryBakery
  # The seed settings, the logger and the explanation helper, extended onto
  # FactoryBakery so the public module stays a readable entry point.
  module SeedApi
    # The seed every generated value derives from, as an Integer. Reading it
    # resolves the seed if that has not happened yet, so it returns the value in
    # use. Resolution order: FACTORY_BAKERY_SEED, then `seed =`, then the test
    # framework's seed, then a random seed for the process.
    # See docs/guide/configuration.md#randomness.
    def seed
      Seed.current.value
    end

    # Sets the seed source: an Integer, or a callable returning one, such as
    # `-> { MyCI.build_number }`. A callable is called once, when the seed is
    # resolved, and must return an Integer. Nil clears the setting so the next
    # source in the order applies. Anything else raises ArgumentError.
    def seed=(value)
      Seed.setting = value
    end

    # Where seed announcements and warnings go. Defaults to stderr; nil silences them.
    def logger
      Seed.logger
    end

    def logger=(value)
      Seed.logger = value
    end

    # Used by the optional integrations (factory_bakery/rspec, factory_bakery/minitest)
    # to make the test framework's seed a seed source. The block returns the
    # framework's seed, or nil when that framework is not running.
    def register_test_framework_seed(label:, reproduce:, &source)
      Seed.register_framework(label:, reproduce:, &source)
    end

    # Text explaining why a record is invalid, for a record built with plain
    # `bake`: the invalid attributes, the random values FactoryBakery chose for
    # them, the seed that reproduces the run and a snippet that pins the value.
    # It runs `valid?` first so the errors are current.
    def explain(record)
      record.valid? if record.respond_to?(:valid?)
      return "#{record.class} is valid; nothing to explain." unless Explanation.errors?(record)

      Explanation.new(record).text
    end
  end
end
