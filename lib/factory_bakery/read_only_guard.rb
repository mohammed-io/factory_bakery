# frozen_string_literal: true

module FactoryBakery
  # Refuses to let bake! write a record whose readonly? is true (a database
  # view, or a single record marked read-only after loading). `bake` never
  # calls this, so read-only targets still get a fully populated unsaved
  # object. Detection and association naming are delegated to the mapper's
  # persistence adapter; the guard itself stays framework-agnostic.
  class ReadOnlyGuard
    def initialize(root, adapter, entries)
      @root = root
      @adapter = adapter
      @entries = entries
    end

    def call
      raise ReadOnlyTargetError, message(root) if read_only?(root)

      found = parent_entry
      return unless found

      parent = found.object
      association = adapter.association_name_for(parent, candidates)
      owner = class_name(found.path[-2])
      raise ReadOnlyTargetError, "#{owner}##{association || 'association'} -> #{message(parent)}"
    end

    private

    attr_reader :root, :adapter, :entries

    # Only records `bake!` would write are guarded. A read-only row that is
    # already persisted (an FK-presence parent adopted from a database view, for
    # example) needs no write, so it is left alone.
    def parent_entry
      entries.find do |entry|
        record = entry.object
        !record.equal?(root) && entry.path.length > 1 && read_only?(record) && !persisted?(record)
      end
    end

    def persisted?(record)
      adapter.persisted?(record)
    end

    def candidates
      @candidates ||= [root, *entries.map(&:object)].uniq
    end

    def read_only?(record)
      MapperRegistry.read_only?(record)
    end

    def class_name(klass)
      klass.respond_to?(:name) && klass.name ? klass.name : klass.to_s
    end

    def message(record)
      "#{class_name(record.class)} is read-only (readonly? is true, e.g. a database view); " \
        'use FactoryBakery.bake to get a populated record, or create the underlying rows yourself. ' \
        'A persist_with hook is not supported yet.'
    end
  end
end
