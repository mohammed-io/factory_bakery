# frozen_string_literal: true

module FactoryBakery
  module Associations
    # Supplies auto-built belongs_to targets to core's heuristic_values hook.
    # :required_only builds required edges; :all builds every non-polymorphic
    # edge, dropping back to required-only past the depth budget. Because these
    # values live in the heuristics layer, declarations, traits, overrides and
    # initialize_with keys suppress them through alias groups.
    module BelongsToBuilder
      REFLECTION_PATH_KEY = :factory_bakery_associations_reflection_path
      SUPPRESSED_EDGES_KEY = :factory_bakery_associations_suppressed_edges

      class << self
        def values(klass, context, taken)
          return {} unless auto_building?
          return {} unless klass.respond_to?(:reflect_on_all_associations)

          reflections_to_build(klass, context).each_with_object({}) do |reflection, values|
            next if suppressed?(reflection, taken)

            require_target!(klass, reflection) if reflection.polymorphic?
            values[reflection.name.to_s] = build_parent(klass, reflection)
          end
        end

        # True for a collection on `klass` that points back to the class whose
        # belongs_to we just followed. :all uses this to skip the return edge.
        def suppressed_edge?(klass, reflection_name)
          suppressed_edges.include?([klass.name, reflection_name.to_s])
        end

        private

        def auto_building?
          %i[required_only all].include?(Associations.mode)
        end

        def reflections_to_build(klass, context)
          reflections = klass.reflect_on_all_associations(:belongs_to)
          required = reflections.select { |reflection| required?(klass, reflection) }
          return required unless Associations.mode == :all && !Associations.past_depth?(context)

          reflections.select { |reflection| !reflection.polymorphic? || required?(klass, reflection) }
        end

        # Heuristic-first detection: Rails materializes "required" as a
        # PresenceValidator on the association name regardless of which setting
        # produced it (including on: :create and if:/unless:), and a NOT NULL FK
        # is required at the database level. `reflection.options[:optional]` is
        # deliberately never read -- plain ActiveRecord defaults it to optional.
        def required?(klass, reflection)
          presence_validator?(klass, reflection) || not_null_fk?(klass, reflection)
        end

        def presence_validator?(klass, reflection)
          klass.validators_on(reflection.name).any? do |validator|
            validator.is_a?(ActiveModel::Validations::PresenceValidator)
          end
        end

        def not_null_fk?(klass, reflection)
          return false unless klass.respond_to?(:columns_hash)

          Array(reflection.foreign_key).any? do |key|
            column = klass.columns_hash[key.to_s]
            column && !column.null
          end
        end

        def suppressed?(reflection, taken)
          alias_members(reflection).any? { |name| taken.include?(name) }
        end

        def alias_members(reflection)
          names = [reflection.name.to_s, *Array(reflection.foreign_key).map(&:to_s)]
          names << reflection.foreign_type.to_s if reflection.polymorphic?
          names.uniq
        end

        # The target class of a polymorphic belongs_to cannot be inferred from
        # the owner side without scanning every model for `as:`.
        def require_target!(klass, reflection)
          name = reflection.name
          raise FactoryBakery::Error,
                "#{klass}##{name} is a required polymorphic association; " \
                "declare it (e.g. association :#{name}, factory: SomeClass) or " \
                "pass #{name}: to name its target"
        end

        # Auto-built edges form a path of reflections (User#account ->
        # Account#owner -> ...). Re-encountering one means an insert cycle that
        # inverse_of cannot make persistable, so raise with the path and an
        # opt-out hint. A finite chain ended by a declaration never repeats an
        # edge and is allowed.
        def build_parent(klass, reflection)
          if ReuseResolver.strategy_for(nil) == :reuse
            existing = ReuseResolver.existing(reflection.klass, {}, reflection)
            return existing if existing
          end

          previous_path = reflection_path
          edge = "#{klass}##{reflection.name}"
          ensure_acyclic!(previous_path, edge)

          Fiber[REFLECTION_PATH_KEY] = previous_path + [edge]
          with_suppressed(BackEdgeDetector.edges(reflection.klass, klass, reflection)) do
            FactoryBakery.bake(reflection.klass)
          end
        ensure
          Fiber[REFLECTION_PATH_KEY] = previous_path
        end

        def ensure_acyclic!(path, edge)
          return unless path.include?(edge)

          hint = path.last.split('#').last
          raise CyclicAssociationError,
                "#{(path + [edge]).join(' -> ')}; " \
                "declare one side (e.g. #{hint} { nil }) or make it optional"
        end

        # Both sets are fiber-local so parallel/fiber-isolated bakes never
        # share them. Each value is replaced (not mutated), so a child fiber
        # cannot alter its parent's state, and `ensure` restores it after every
        # edge.
        def with_suppressed(edges)
          previous = suppressed_edges
          Fiber[SUPPRESSED_EDGES_KEY] = (previous + edges).uniq.freeze
          yield
        ensure
          Fiber[SUPPRESSED_EDGES_KEY] = previous
        end

        def suppressed_edges
          Fiber[SUPPRESSED_EDGES_KEY] ||= [].freeze
        end

        def reflection_path
          Fiber[REFLECTION_PATH_KEY] ||= [].freeze
        end
      end
    end
  end
end
