# frozen_string_literal: true

module FactoryBakery
  # The seed settings, the logger and the explanation helper, extended onto
  # FactoryBakery so the public module stays a readable entry point.
  module SeedApi
    # The seed every generated value derives from (an Integer). It is resolved
    # on first use: FACTORY_BAKERY_SEED, then `seed=`, then `seed_generator`,
    # then the test framework's seed, then a random seed for the process.
    # See docs/guide/configuration.md#randomness.
    def seed
      Seed.current.value
    end

    # Nil clears the setting so the next source in the order applies.
    def seed=(value)
      Seed.explicit = value
    end

    # A callable returning an Integer, consulted when neither the environment
    # variable nor `seed=` is set. Nil clears it.
    def seed_generator
      Seed.generator
    end

    def seed_generator=(callable)
      Seed.generator = callable
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
