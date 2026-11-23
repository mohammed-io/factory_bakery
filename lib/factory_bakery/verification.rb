# frozen_string_literal: true

module FactoryBakery
  # The per-call (or nested-scope) `validate:` value, fiber-local like
  # FillOptional's scope so a bake made by a definition block inherits the
  # caller's choice.
  module Verification
    SCOPE_KEY = :factory_bakery_validate_override

    class << self
      # Scopes the block to an explicit `validate:` value. `nil` changes
      # nothing: a bake that was not given the keyword inherits the enclosing
      # scope, or the global setting when no scope is active.
      def with(value)
        return yield if value.nil?

        previous = Fiber[SCOPE_KEY]
        Fiber[SCOPE_KEY] = value
        yield
      ensure
        Fiber[SCOPE_KEY] = previous
      end

      # The active per-call override, or nil when the global setting applies.
      def override
        Fiber[SCOPE_KEY]
      end
    end
  end
end
