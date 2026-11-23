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

    REBUILD_ERRORS_KEY = :factory_bakery_rebuild_error_attributes

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
      #
      # `error_attributes` are the names the lean probe's errors carried. An
      # optional `belongs_to` the probe blamed is built during the rebuild like
      # a required edge, because a custom validator (Discourse's
      # `PostValidator` adding "Topic can't be blank") demands it even though
      # no discovered constraint does.
      def with_rebuild(depth, error_attributes: nil, &block)
        previous = Fiber[REBUILD_DEPTH_KEY]
        previous_errors = Fiber[REBUILD_ERRORS_KEY]
        Fiber[REBUILD_DEPTH_KEY] = depth
        Fiber[REBUILD_ERRORS_KEY] = Array(error_attributes).map(&:to_s).freeze
        with(true, &block)
      ensure
        Fiber[REBUILD_DEPTH_KEY] = previous
        Fiber[REBUILD_ERRORS_KEY] = previous_errors
      end

      # True for a bake at `depth` that is nested inside a rebuild, i.e. not
      # the record the rebuild is filling. The rebuild's own build never goes
      # through `FactoryBakery.bake`, so every call that sees this is nested.
      def nested_in_rebuild?(depth)
        floor = Fiber[REBUILD_DEPTH_KEY]
        !floor.nil? && depth >= floor
      end

      # The names the lean probe of the rebuild currently in flight blamed, or
      # [] outside one. Read by the belongs_to auto-build.
      def rebuild_error_attributes
        Fiber[REBUILD_ERRORS_KEY] || []
      end

      # Normalizes a call-site or global `fill_optional` value: `nil` falls
      # back to the current scope, `true` / `false` pass, an Array of names is
      # stringified, and anything else raises ArgumentError.
      def normalize(value)
        return current if value.nil?
        return value if [true, false].include?(value)
        return value.map(&:to_s) if value.is_a?(Array)

        raise ArgumentError, "fill_optional must be true, false, or an array of attribute names, got #{value.inspect}"
      end

      # The blamed names describe the one record being rebuilt. A bake nested
      # inside that rebuild (a parent, a declaration's own bake) is a separate
      # record, so it runs with no names: otherwise an outer error on `user_id`
      # would build every nested record's optional `user` too.
      def for_bake_at(depth)
        return yield unless nested_in_rebuild?(depth) && rebuild_error_attributes.any?

        previous = Fiber[REBUILD_ERRORS_KEY]
        Fiber[REBUILD_ERRORS_KEY] = [].freeze
        yield
      ensure
        Fiber[REBUILD_ERRORS_KEY] = previous if previous
      end

      def with(value)
        previous = Fiber[SCOPE_KEY]
        Fiber[SCOPE_KEY] = value
        yield
      ensure
        Fiber[SCOPE_KEY] = previous
      end

      # The scope stack every public bake runs under: the rebuild scoping for
      # the bake's depth plus the resolved mode.
      def around_bake(depth, mode, &block)
        for_bake_at(depth) { with(mode, &block) }
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
        Fiber[REBUILD_ERRORS_KEY] = nil
      end
    end
  end
end
