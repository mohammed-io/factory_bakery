# frozen_string_literal: true

module FactoryBakery
  module Associations
    # Finds the collection edges on a belongs_to target that point back to
    # the class we arrived from. Following Post#author must not make Author
    # rebuild its Post collection, so :all records these edges as suppressed.
    #
    # Pure logic over the mapper's association introspection: candidates,
    # foreign keys and inverses arrive as plain data.
    module BackEdgeDetector
      class << self
        def edges(target_class, source_klass, entry)
          introspection = FactoryBakery::MapperRegistry.association_introspection(target_class)
          return [] unless introspection

          introspection
            .select { |candidate| back_edge?(candidate, source_klass, entry) }
            .map { |candidate| [target_class.name, candidate.name] }
        end

        private

        def back_edge?(candidate, source_klass, entry)
          return false unless %i[has_one has_many].include?(candidate.kind)
          return true if inverse?(candidate, entry)
          return false unless foreign_keys_match?(candidate, entry)

          same_class?(candidate, source_klass)
        end

        def inverse?(candidate, entry)
          inverse = entry.inverse_name.call
          !inverse.nil? && inverse.to_s == candidate.name
        end

        def foreign_keys_match?(candidate, entry)
          (candidate.foreign_keys & entry.foreign_keys).any?
        end

        # The target resolves lazily, exactly as reading it off the
        # reflection does: an unloadable candidate is simply not a back edge.
        def same_class?(candidate, source_klass)
          candidate.target.call == source_klass
        rescue NameError
          false
        end
      end
    end
  end
end
