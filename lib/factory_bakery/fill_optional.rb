# frozen_string_literal: true

module FactoryBakery
  # Controls whether a default bake fills columns a valid record does not
  # need. Off by default; opt in globally with `FactoryBakery.fill_optional =`
  # (or `FactoryBakery.configure`) or for one call with
  # `bake(Model, fill_optional: true)`. A list of names opts in just those.
  #
  # The effective value is fiber-local so nested bakes inherit the caller's
  # choice and the verified-fallback rebuild can fill everything without
  # triggering another fallback in the parents it rebuilds.
  module FillOptional
    SCOPE_KEY = :factory_bakery_fill_optional

    class << self
      def global
        @global ||= false
      end

      attr_writer :global

      def current
        scoped = Fiber[SCOPE_KEY]
        scoped.nil? ? global : scoped
      end

      def with(value)
        previous = Fiber[SCOPE_KEY]
        Fiber[SCOPE_KEY] = value
        yield
      ensure
        Fiber[SCOPE_KEY] = previous
      end

      def full?(mode)
        mode == true
      end

      def includes?(mode, name)
        mode == true || (mode.is_a?(Array) && mode.include?(name.to_s))
      end

      # Test support: restores the default and clears this fiber's scope.
      def reset!
        @global = false
        Fiber[SCOPE_KEY] = nil
      end
    end
  end
end
