# frozen_string_literal: true

require 'set'

module FactoryBakery
  # After the root `save!`, checks that every record generated anywhere in the
  # bake graph actually reached the database. Framework autosave options such
  # as `autosave: false` or `validate: false` can leave an associated object
  # new even though the root saved successfully; returning such a graph would
  # hand the caller a half-persisted object.
  #
  # All persistence and association questions are asked through the mapper's
  # persistence adapter, so the verifier itself is framework-agnostic.
  class PersistenceVerifier
    def initialize(root, entries, adapter)
      @root = root
      @entries = entries
      @adapter = adapter
    end

    def call
      unsaved = @entries.reject { |_path, record| @adapter.persisted?(record) }
      return if unsaved.empty?

      superseded = superseded_records(unsaved)
      unsaved.reject! { |_path, record| superseded.include?(record) }
      return if unsaved.empty?

      raise IncompletePersistenceError, message_for(unsaved)
    end

    private

    # A callback may replace an automatic parent or clear an optional one.
    # Its unused subtree can be ignored unless another kept record still
    # references it. User-declared records start out as kept.
    def superseded_records(unsaved)
      return [] unless @adapter.respond_to?(:automatic_parent_discarded?)

      unsaved_records = Set.new.compare_by_identity.merge(unsaved.map { |_path, record| record })
      candidates = superseded_candidates(unsaved_records)
      return candidates if candidates.empty?

      retained = reachable_records(candidates)
      candidates.delete_if { |record| retained.include?(record) }
    end

    def superseded_candidates(unsaved_records)
      records = BuildContext.automatic_parents
                            .select { |edge| unsaved_records.include?(edge.parent) }
                            .select { |edge| @adapter.automatic_parent_discarded?(edge) }
                            .flat_map(&:records)
      Set.new.compare_by_identity.merge(records)
    end

    def reachable_records(candidates)
      pending = [@root, *@entries.map { |_path, record| record }.reject { |record| candidates.include?(record) }]
      seen = Set.new.compare_by_identity
      until pending.empty?
        record = pending.pop
        next unless seen.add?(record)

        pending.concat(@adapter.cached_association_targets(record))
      end
      seen
    end

    def message_for(unsaved)
      objects = [@root, *@entries.map { |_path, record| record }].uniq

      details = unsaved.map do |_path, record|
        name = record.class.name || record.class.to_s
        association = @adapter.association_name_for(record, objects)
        association ? "#{name} (assigned to #{association})" : name
      end

      "bake! did not persist all generated records: #{details.join(', ')}. " \
        'Persist the record explicitly via a declaration or override, ' \
        "or change the association's autosave/validate options."
    end
  end
end
