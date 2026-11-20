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

    REBUILD_DEPTH_KEY = :factory_bakery_rebuild_depth

    class << self
      def global
        @global ||= false
      end

      attr_writer :global

      def current
        scoped = Fiber[SCOPE_KEY]
        scoped.nil? ? global : scoped
      end

      # The verified fallback fills every optional column of the one record it
      # rebuilds. A nested bake (a parent built by a declaration or an
      # association) is a separate record with its own verified fallback, so
      # the rebuild's opt-in must stop at the record being rebuilt: deeper
      # bakes stay lean instead of turning their own parents into fuller
      # records that may fail their validation. `depth` is the build-path
      # length of the record being rebuilt.
      def with_rebuild(depth, &block)
        previous = Fiber[REBUILD_DEPTH_KEY]
        Fiber[REBUILD_DEPTH_KEY] = depth
        with(true, &block)
      ensure
        Fiber[REBUILD_DEPTH_KEY] = previous
      end

      # True for a bake at `depth` that is nested inside a rebuild, i.e. not
      # the record the rebuild is filling. The rebuild's own build never goes
      # through `FactoryBakery.bake`, so every call that sees this is nested.
      def nested_in_rebuild?(depth)
        floor = Fiber[REBUILD_DEPTH_KEY]
        !floor.nil? && depth >= floor
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
        Fiber[REBUILD_DEPTH_KEY] = nil
      end
    end
  end
end
