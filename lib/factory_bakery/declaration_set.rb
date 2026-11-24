# frozen_string_literal: true

module FactoryBakery
  # The attributes one layer of a definition declares: an ordered, frozen list
  # of `[name, value_block]` pairs, the same names as frozen strings, the
  # plugin declarations the layer made (`[plugin, entry]`, in order) and, for a
  # definition's base layer, the trait blocks it registered. A layer is a
  # definition's own block or one trait's block; composing the base with the
  # requested traits gives the full declaration list a build reads.
  #
  # Pure data: it never runs a block. See ADR-0009 for why a declaration layer
  # can be recorded once.
  class DeclarationSet
    NONE = [].freeze

    attr_reader :pairs, :names, :trait_procs, :plugin_entries

    # The base layer followed by each requested trait layer, in the order the
    # traits were requested (a later declaration of a name wins).
    def self.compose(base, trait_layers)
      return base if trait_layers.empty?

      new(base.pairs + trait_layers.flat_map(&:pairs),
          trait_procs: base.trait_procs,
          plugin_entries: base.plugin_entries + trait_layers.flat_map(&:plugin_entries))
    end

    def initialize(pairs, trait_procs: {}, plugin_entries: NONE)
      @pairs = pairs.freeze
      @names = pairs.map { |name, _block| name.to_s.freeze }.freeze
      @trait_procs = trait_procs.freeze
      @plugin_entries = plugin_entries.freeze
      freeze
    end

    # What a target with no definition block declares: nothing, shared.
    EMPTY = new([]).freeze
  end
end
