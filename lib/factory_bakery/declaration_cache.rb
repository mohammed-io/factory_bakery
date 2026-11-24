# frozen_string_literal: true

module FactoryBakery
  # What a registered definition declares, recorded once and reused by every
  # later bake (ADR-0008): the base layer, each trait's layer, and the
  # compositions of base and traits that were requested. Layers are
  # `DeclarationSet`s. Per-call overrides are not part of it; they are
  # combined with a cached set on each bake (`BakeryBuilder::Names`).
  #
  # The cache hangs off the definition's own block, so registering the name
  # again (a new block) leaves the old cache unreachable: nothing to
  # invalidate, and nothing to leak.
  #
  # Only plain declarations are recorded. A layer that made a non-reusable
  # plugin declaration or called `initialize_with` is never stored, so those
  # definitions evaluate on every bake exactly as before. Nothing is stored
  # until a layer was recorded without raising.
  #
  # The cache is never cleared. What a block declares depends on which plugin
  # DSL was available when it ran, so each cache publishes one
  # `(scope, entries)` pair and `for_plugins` hands a build the entries for
  # its scope, captured once: a build that meets a registry change keeps
  # reading and writing its own pair, and a build under a changed scope
  # records into a fresh pair and publishes it with a single assignment. The
  # old pair becomes unreachable with the builders that captured it, so
  # churn in the plugin set cannot grow memory. Each pair of entries also
  # remembers the process-wide generation it was recorded under -- bumped
  # when a reload or `reset_cache!` makes recorded layers untrustworthy --
  # and a stale generation reads as not cached.
  class DeclarationCache
    IVAR = :@factory_bakery_declarations

    # Publishing the one cache of a definition block is the only shared
    # mutation, and it happens under this mutex: two threads that meet on
    # first use both record (the declaration layer is pure, ADR-0008) and the
    # loser adopts the winner's cache. Never held while a block runs.
    PUBLISH_MUTEX = Mutex.new

    class << self
      # The process-wide generation of recorded declarations: an Integer
      # published with a single assignment, so a reader sees the old or the
      # new value, never a mixture.
      def generation
        @generation ||= 0
      end

      # Called when recorded declaration layers can no longer be trusted: a
      # framework reload replaced the classes a recorded layer evaluated, or
      # `reset_cache!` dropped the per-class facts under it. Layers recorded
      # under an older generation read as not cached and are recorded again.
      def bump_generation
        @generation = generation + 1
      end

      # The cache of a definition block, created on first use. A frozen block
      # cannot carry one, and then every bake evaluates it.
      def for(builder_proc)
        return unless builder_proc

        builder_proc.instance_variable_get(IVAR) || PUBLISH_MUTEX.synchronize do
          builder_proc.instance_variable_get(IVAR) ||
            builder_proc.instance_variable_set(IVAR, new)
        end
      rescue FrozenError
        nil
      end
    end

    # The entries recorded for one plugin scope, captured once per build:
    # every later read and write of that build goes to the object returned
    # here, so a registration that happens mid-build can neither corrupt it
    # nor be corrupted by it. A scope that is no longer current is simply no
    # longer published; its entries become unreachable with the builders that
    # captured them.
    def for_plugins(scope)
      store = @store
      return store if store&.answers_for?(scope)

      ScopeStore.new(scope).tap { |fresh| @store = fresh }
    end

    # The entries one plugin scope recorded: the base layer, each trait's
    # layer and the compositions of base and traits requested so far.
    # Mutable, but only in the entries of the scope it answers for; the
    # declaration layer is pure (ADR-0008), so two concurrent first
    # recordings write equivalent sets and either result is correct.
    class ScopeStore
      attr_reader :scope, :generation, :base

      def initialize(scope)
        @scope = scope
        @generation = DeclarationCache.generation
        @base = nil
        @traits = {}
        @composed = {}
      end

      # Answers only for the scope it was recorded under and the generation
      # it was recorded in: a registry change or a reload starts it over.
      def answers_for?(scope)
        self.scope.equal?(scope) && generation == DeclarationCache.generation
      end

      def store_base(set)
        @base = set
      end

      def trait(name)
        @traits[name]
      end

      def store_trait(name, set)
        @traits[name] = set
      end

      # The full declaration list for the requested traits, or nil when it
      # has not been recorded yet. A bake with no traits is the base layer
      # itself.
      def composed(traits)
        traits.empty? ? @base : @composed[traits]
      end

      def store_composed(traits, set)
        @composed[traits.dup.freeze] = set unless traits.empty?
      end
    end
  end
end
