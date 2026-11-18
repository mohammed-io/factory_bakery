# frozen_string_literal: true

module FactoryBakery
  module Associations
    # Finds the collection reflections on a belongs_to target that point back
    # to the class we arrived from. Following Post#author must not make Author
    # rebuild its Post collection, so :all records these edges as suppressed.
    module BackEdgeDetector
      class << self
        def edges(target, source_klass, reflection)
          return [] unless target.respond_to?(:reflect_on_all_associations)

          target.reflect_on_all_associations
                .select { |candidate| back_edge?(candidate, source_klass, reflection) }
                .map { |candidate| [target.name, candidate.name.to_s] }
        end

        private

        def back_edge?(candidate, source_klass, reflection)
          return false unless %i[has_one has_many].include?(candidate.macro)
          return true if inverse?(candidate, reflection)
          return false unless foreign_keys_match?(candidate, reflection)

          same_class?(candidate, source_klass)
        end

        def inverse?(candidate, reflection)
          inverse = reflection.inverse_of
          !inverse.nil? && inverse.name == candidate.name
        end

        def foreign_keys_match?(candidate, reflection)
          candidate_keys = Array(candidate.foreign_key).map(&:to_s)
          reflection_keys = Array(reflection.foreign_key).map(&:to_s)
          (candidate_keys & reflection_keys).any?
        end

        def same_class?(candidate, source_klass)
          candidate.klass == source_klass
        rescue NameError
          false
        end
      end
    end
  end
end
