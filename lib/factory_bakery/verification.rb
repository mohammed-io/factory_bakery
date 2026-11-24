# frozen_string_literal: true

require_relative 'fiber_local'

module FactoryBakery
  # The per-call (or nested-scope) `validate:` value. It lives in fiber-local
  # storage that child fibers do not inherit (see FiberLocal): a bake made by a
  # definition block, on the same fiber, inherits the caller's choice, while a
  # fiber or thread started inside a bake is an independent unit of work and
  # sees the global setting, whether the bake that started it is still running
  # or not.
  module Verification
    SCOPE_KEY = :factory_bakery_validate_override

    class << self
      # Scopes the block to an explicit `validate:` value. `nil` changes
      # nothing: a bake that was not given the keyword inherits the enclosing
      # scope, or the global setting when no scope is active.
      def with(value)
        return yield if value.nil?

        previous = FiberLocal[SCOPE_KEY]
        FiberLocal[SCOPE_KEY] = value
        yield
      ensure
        # The previous override is restored on every exit of a scoping call.
        FiberLocal[SCOPE_KEY] = previous unless value.nil?
      end

      # The active per-call override, or nil when the global setting applies.
      def override
        FiberLocal[SCOPE_KEY]
      end
    end
  end
end
