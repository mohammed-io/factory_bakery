# frozen_string_literal: true

module FactoryBakery
  # The per-call (or nested-scope) `validate:` value, fiber-local like
  # FillOptional's scope so a bake made by a definition block inherits the
  # caller's choice.
  module Verification
    SCOPE_KEY = :factory_bakery_validate_override

    # The active per-call override with whether its bake is still running.
    # `Fiber[]` storage is inherited by child fibers, so a fiber created
    # inside a bake and resumed after the bake returned must not keep the
    # override -- `active` says when it has expired, like Randomness::Scope.
    Scope = Struct.new(:value, :active)

    class << self
      # Scopes the block to an explicit `validate:` value. `nil` changes
      # nothing: a bake that was not given the keyword inherits the enclosing
      # scope, or the global setting when no scope is active.
      def with(value)
        return yield if value.nil?

        previous = Fiber[SCOPE_KEY]
        scope = Scope.new(value, true)
        Fiber[SCOPE_KEY] = scope
        yield
      ensure
        # The previous override is restored on every exit of a scoping call,
        # and the scope is deactivated before it is, so a child fiber that
        # inherited the storage stops seeing it too.
        scope&.active = false
        Fiber[SCOPE_KEY] = previous if scope
      end

      # The active per-call override, or nil when the global setting applies.
      def override
        stored = Fiber[SCOPE_KEY]
        stored.value if stored&.active
      end
    end
  end
end
