# frozen_string_literal: true

module FactoryBakery
  class BakeryBuilder
    # The name lists a single build reads. Everything fixed at declaration
    # time is snapshotted once per build -- each build used to recompute the
    # same lists at every layer that reads them (taken names, suppression,
    # explicit reservation, winning blocks), so one `bake` normalized the same
    # hashes and re-derived the same name arrays a dozen times. The
    # plugin-declared names are the one exception: a plugin DSL call inside an
    # attribute block records its declaration only when that block runs, which
    # happens after the snapshot's inputs were taken, so those names are read
    # live from the builder's own bucket hash on every ask.
    #
    # Every list it hands out is frozen, so a reader cannot corrupt a list
    # another layer shares; the object itself is never reused across builds,
    # so nothing can go stale.
    class Names
      # Shared frozen empties for the no-declaration fast paths: callers only
      # read or merge the result, never mutate it.
      EMPTY_HASH = {}.freeze
      EMPTY_ARRAY = [].freeze

      attr_reader :overrides, :initialize_with, :declared,
                  :override_keys, :init_with_keys, :explicit,
                  :suppression_seeds

      def initialize(declaration_stream:, plugin_declarations:, overrides:, initialize_with:)
        @plugin_declarations = plugin_declarations
        @overrides = normalize_keys(overrides).freeze
        @initialize_with = normalize_keys(initialize_with).freeze
        @declared = declared_names(declaration_stream)
        @override_keys = @overrides.keys.freeze
        @init_with_keys = @initialize_with.keys.freeze
        @explicit = combine(@declared, @override_keys)
        @suppression_seeds = combine(@declared, @override_keys, @init_with_keys)
      end

      # Read live: a declaration recorded by a plugin DSL call that ran inside
      # an attribute block exists only after this object was built.
      def plugin_declared
        declarations = @plugin_declarations
        return EMPTY_ARRAY if declarations.nil? || declarations.empty?

        plugin_declared_names(declarations)
      end

      def raw_taken
        (@declared + plugin_declared + @override_keys + @init_with_keys).freeze
      end

      private

      def plugin_declared_names(declarations)
        declarations.values.flatten.map do |entry|
          entry.respond_to?(:name) ? entry.name.to_s : entry.to_s
        end.freeze
      end

      def declared_names(stream)
        stream.map { |name, _block| name.to_s }.freeze
      end

      # Freezes the shared derived list, so a reader cannot corrupt a list
      # another layer reads too.
      def combine(*lists)
        lists.reduce(:+).freeze
      end

      def normalize_keys(hash)
        return EMPTY_HASH if hash.nil? || hash.empty?

        hash.transform_keys(&:to_s)
      end
    end
  end
end
