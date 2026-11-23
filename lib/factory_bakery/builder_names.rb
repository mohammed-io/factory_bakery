# frozen_string_literal: true

module FactoryBakery
  class BakeryBuilder
    # One immutable snapshot of every name list a single build needs. Each
    # build used to recompute the same lists at every layer that reads them
    # (taken names, suppression, explicit reservation, winning blocks), so one
    # `bake` normalized the same hashes and re-derived the same name arrays a
    # dozen times. The snapshot is built once per `build`, right after the
    # declarations have been evaluated, because from that point on the inputs
    # are final: the declaration stream, the plugin declaration buckets, the
    # call-site overrides and the initialize_with attributes no longer change
    # for the rest of the build. Every list it hands out is frozen, so a
    # reader cannot corrupt a list another layer shares; the object itself is
    # never reused across builds, so nothing can go stale.
    class Names
      # Shared frozen empty hash for `normalize_keys`' fast path: callers only
      # read or merge the result, never mutate it.
      EMPTY_HASH = {}.freeze

      attr_reader :overrides, :initialize_with, :declared, :plugin_declared,
                  :override_keys, :init_with_keys, :raw_taken, :explicit,
                  :suppression_seeds

      def initialize(declaration_stream:, plugin_declarations:, overrides:, initialize_with:)
        @overrides = normalize_keys(overrides).freeze
        @initialize_with = normalize_keys(initialize_with).freeze
        @declared = declared_names(declaration_stream)
        @plugin_declared = plugin_declared_names(plugin_declarations)
        @override_keys = @overrides.keys.freeze
        @init_with_keys = @initialize_with.keys.freeze
        @raw_taken = combine(@declared, @plugin_declared, @override_keys, @init_with_keys)
        @explicit = combine(@declared, @override_keys)
        @suppression_seeds = combine(@declared, @override_keys, @init_with_keys)
      end

      private

      def declared_names(stream)
        stream.map { |name, _block| name.to_s }.freeze
      end

      def plugin_declared_names(declarations)
        (declarations || {}).values.flatten.map do |entry|
          entry.respond_to?(:name) ? entry.name.to_s : entry.to_s
        end.freeze
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
