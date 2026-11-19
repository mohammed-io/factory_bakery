# frozen_string_literal: true

module FactoryBakery
  module Associations
    # Supplies auto-built belongs_to targets to core's heuristic_values hook.
    # :required_only builds required edges; :all builds every non-polymorphic
    # edge, dropping back to required-only past the depth budget. Because these
    # values live in the heuristics layer, declarations, traits, overrides and
    # initialize_with keys suppress them through alias groups.
    #
    # Which edges exist (and which are required) arrives as plain association
    # introspection from the mapper contract; the logic below is pure
    # orchestration over that data.
    module BelongsToBuilder
      REFLECTION_PATH_KEY = :factory_bakery_associations_reflection_path
      SUPPRESSED_EDGES_KEY = :factory_bakery_associations_suppressed_edges

      class << self
        def values(klass, context, taken)
          return {} unless auto_building?

          introspection = FactoryBakery::MapperRegistry.association_introspection(klass)
          return {} unless introspection

          entries_to_build(introspection, context).each_with_object({}) do |entry, values|
            next if suppressed?(entry, taken)

            require_target!(klass, entry) if entry.polymorphic
            values[entry.name] = build_parent(klass, entry)
          end
        end

        # True for a collection on `klass` that points back to the class whose
        # belongs_to we just followed. :all uses this to skip the return edge.
        def suppressed_edge?(klass, entry_name)
          suppressed_edges.include?([klass.name, entry_name.to_s])
        end

        private

        def auto_building?
          %i[required_only all].include?(Associations.mode)
        end

        def entries_to_build(introspection, context)
          belongs_to = introspection.select { |entry| entry.kind == :belongs_to }
          required = belongs_to.select(&:required)
          return required unless Associations.mode == :all && !Associations.past_depth?(context)

          belongs_to.select { |entry| !entry.polymorphic || entry.required }
        end

        def suppressed?(entry, taken)
          alias_members(entry).any? { |name| taken.include?(name) }
        end

        def alias_members(entry)
          names = [entry.name, *entry.foreign_keys]
          names << entry.foreign_type if entry.polymorphic
          names.uniq
        end

        # The target class of a polymorphic belongs_to cannot be inferred from
        # the owner side without scanning every model for `as:`.
        def require_target!(klass, entry)
          name = entry.name
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
        def build_parent(klass, entry)
          target_class = entry.target.call
          reuse = ReuseResolver.strategy_for(nil) == :reuse
          if reuse
            existing = ReuseResolver.existing(target_class, {}, entry)
            return existing if existing
          end

          previous_path = reflection_path
          edge = "#{klass}##{entry.name}"
          ensure_acyclic!(previous_path, edge)

          Fiber[REFLECTION_PATH_KEY] = previous_path + [edge]
          with_suppressed(BackEdgeDetector.edges(target_class, klass, entry)) do
            fresh = FactoryBakery.bake(target_class)
            ReuseResolver.remember(target_class, {}, entry, fresh) if reuse
            fresh
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
