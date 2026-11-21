# frozen_string_literal: true

module FactoryBakery
  # Opt-in mixin that exposes bare +bake+ and +bake!+ inside tests, delegating
  # to the module-level API. The gem never installs these methods globally.
  #
  # RSpec:
  #   RSpec.configure { |config| config.include FactoryBakery::Methods }
  #
  # Minitest:
  #   class UserTest < Minitest::Test
  #     include FactoryBakery::Methods
  #   end
  module Methods
    # Builds an unsaved object. Accepts the same target, traits and overrides
    # as FactoryBakery.bake.
    def bake(target, *traits, **overrides, &block)
      FactoryBakery.bake(target, *traits, **overrides, &block)
    end

    # Builds and persists the object when it responds to +save!+.
    def bake!(target, *traits, **overrides, &block)
      FactoryBakery.bake!(target, *traits, **overrides, &block)
    end
  end
end
