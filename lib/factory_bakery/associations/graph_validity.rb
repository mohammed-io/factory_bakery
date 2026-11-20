# frozen_string_literal: true

module FactoryBakery
  module Associations
    # A required belongs_to is satisfied by any parent object, valid or not.
    # When the graph is inserted, the framework's autosave quietly skips an
    # invalid unsaved parent and writes the child with a nil foreign key. So
    # validity here means: the record is valid and so is every unsaved parent
    # it requires, transitively.
    #
    # A parent whose own build has not returned yet (the owner a child is
    # being built for, or any owner above it) is never judged: it is
    # incomplete by definition, and validating it early would run its
    # callbacks before it is filled (Discourse's User loads `primary_email` in
    # `before_validation`, which then reads as already decided).
    #
    # The required edges come from the mapper's association introspection;
    # reading an edge is the model's public reader.
    module GraphValidity
      class << self
        # Can a best-effort :all child be kept?
        def invalid?(record)
          !first_invalid(record, {}.compare_by_identity).nil?
        end

        # The first unsaved required parent (transitively) that is invalid,
        # for a record about to be inserted; nil when all are valid.
        def first_invalid_parent(record)
          seen = { record => true }.compare_by_identity
          unsaved_required_parents(record).lazy.filter_map { |parent| first_invalid(parent, seen) }.first
        end

        private

        def first_invalid(record, seen)
          return nil if seen.key?(record)

          seen[record] = true
          return nil unless record.respond_to?(:valid?)
          return record unless record.valid?

          unsaved_required_parents(record).lazy.filter_map { |parent| first_invalid(parent, seen) }.first
        rescue StandardError
          record
        end

        def unsaved_required_parents(record)
          introspection = FactoryBakery::MapperRegistry.association_introspection(record.class)
          return [] unless introspection

          introspection
            .select { |entry| entry.kind == :belongs_to && entry.required }
            .filter_map { |entry| record.public_send(entry.name) }
            .select { |parent| judgeable?(parent) }
        end

        def judgeable?(parent)
          parent.respond_to?(:new_record?) && parent.new_record? && !BuildContext.in_progress?(parent)
        end
      end
    end
  end
end
