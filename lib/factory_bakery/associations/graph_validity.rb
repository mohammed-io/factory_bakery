# frozen_string_literal: true

module FactoryBakery
  module Associations
    # Decides whether a best-effort :all child can be kept. A record's own
    # `valid?` is not enough: a required belongs_to is satisfied by any parent
    # object, valid or not, and when the graph is inserted the framework's
    # autosave quietly skips an invalid unsaved parent and writes the child
    # with a nil foreign key. So a kept child must be valid and so must every
    # unsaved parent it requires, transitively.
    #
    # The required edges come from the mapper's association introspection;
    # reading an edge is the model's public reader.
    module GraphValidity
      class << self
        def invalid?(record)
          invalid_from?(record, {}.compare_by_identity)
        end

        private

        def invalid_from?(record, seen)
          return false if seen.key?(record)

          seen[record] = true
          return false unless record.respond_to?(:valid?)
          return true unless record.valid?

          unsaved_required_parents(record).any? { |parent| invalid_from?(parent, seen) }
        rescue StandardError
          true
        end

        def unsaved_required_parents(record)
          introspection = FactoryBakery::MapperRegistry.association_introspection(record.class)
          return [] unless introspection

          introspection
            .select { |entry| entry.kind == :belongs_to && entry.required }
            .filter_map { |entry| record.public_send(entry.name) }
            .select { |parent| parent.respond_to?(:new_record?) && parent.new_record? }
        end
      end
    end
  end
end
