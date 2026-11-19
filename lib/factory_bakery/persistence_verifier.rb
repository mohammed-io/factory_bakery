# frozen_string_literal: true

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

      raise IncompletePersistenceError, message_for(unsaved)
    end

    private

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
