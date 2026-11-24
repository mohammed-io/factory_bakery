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
  # Only plain declarations are recorded. A layer that made a plugin
  # declaration or called `initialize_with` is never stored, so those
  # definitions evaluate on every bake exactly as before. Nothing is stored
  # until a layer was recorded without raising.
  class DeclarationCache
    IVAR = :@factory_bakery_declarations

    class << self
      # The cache of a definition block, created on first use. A frozen block
      # cannot carry one, and then every bake evaluates it.
      def for(builder_proc)
        return unless builder_proc

        builder_proc.instance_variable_get(IVAR) || builder_proc.instance_variable_set(IVAR, new)
      rescue FrozenError
        nil
      end
    end

    attr_reader :base

    def initialize
      @plugin_scope = nil
      clear
    end

    # What was recorded depends on which plugin DSL was available when the
    # blocks ran (a plugin registered or removed changes what a block means),
    # so a cache answers only for the plugin scope it was recorded under and
    # starts over when that changes. Returns self.
    def for_plugins(scope)
      return self if scope.equal?(@plugin_scope)

      clear
      @plugin_scope = scope
      self
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

    # The full declaration list for the requested traits, or nil when it has
    # not been recorded yet. A bake with no traits is the base layer itself.
    def composed(traits)
      traits.empty? ? @base : @composed[traits]
    end

    def store_composed(traits, set)
      @composed[traits.dup.freeze] = set unless traits.empty?
    end

    private

    def clear
      @base = nil
      @traits = {}
      @composed = {}
    end
  end
end
