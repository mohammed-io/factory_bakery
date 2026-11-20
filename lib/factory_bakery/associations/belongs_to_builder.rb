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
    module BelongsToBuilder # rubocop:disable Metrics/ModuleLength
      REFLECTION_PATH_KEY = :factory_bakery_associations_reflection_path
      SUPPRESSED_EDGES_KEY = :factory_bakery_associations_suppressed_edges

      class << self # rubocop:disable Metrics/ClassLength
        def values(klass, context, taken)
          return {} unless auto_building?

          introspection = FactoryBakery::MapperRegistry.association_introspection(klass)
          return {} unless introspection

          entries_to_build(introspection, context).each_with_object({}) do |entry, values|
            next if suppressed?(entry, taken)

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
          belongs_to = introspection.select { |entry| id_keyed_belongs_to?(entry) }
          required = belongs_to.select(&:required)
          return required unless Associations.mode == :all && !Associations.past_depth?(context)

          belongs_to.select { |entry| !entry.polymorphic || entry.required }
        end

        # Natural keys are handled after instantiation by NaturalKeyBuilder,
        # once the child's own key value is known.
        def id_keyed_belongs_to?(entry)
          entry.kind == :belongs_to && entry.natural_key_name.nil?
        end

        def suppressed?(entry, taken)
          alias_members(entry).any? { |name| taken.include?(name) }
        end

        def alias_members(entry)
          names = [entry.name, *entry.foreign_keys]
          names << entry.foreign_type if entry.polymorphic
          names.uniq
        end

        # A polymorphic edge asks the mapper for candidate classes; an ordinary
        # one resolves its target directly. Both arrive as plain data.
        #
        # A candidate that fails is discarded whole: its savepoint rolls back
        # any row its FK-presence parent inserted, and the generated-record
        # mark drops the records it built so `bake!` verifies only the graph
        # that was kept (otherwise a failed candidate's unsaved parent fails
        # the winning bake).
        def build_parent(klass, entry)
          discovered = entry.polymorphic ? polymorphic_targets(klass, entry) : direct_targets(entry)
          failures = []
          discovered.candidates.each do |target|
            mark = BuildContext.generated_records.length
            begin
              return attempt_candidate(klass, entry, target)
            rescue StandardError => e
              BuildContext.trim_generated_records!(mark)
              failures << [target, e]
            end
          end

          raise_unresolved!(klass, entry, discovered, failures)
        end

        def attempt_candidate(klass, entry, target)
          adapter = FactoryBakery::MapperRegistry.persistence_adapter(klass)
          return build_for_target(klass, entry, target) unless adapter.transactional?

          adapter.transaction(klass) { build_for_target(klass, entry, target) }
        end

        def direct_targets(entry)
          FactoryBakery::MapperRegistry::DiscoveredTargets.new(
            candidates: [entry.resolve_target].freeze, sources: [].freeze
          )
        end

        def polymorphic_targets(klass, entry)
          FactoryBakery::MapperRegistry.polymorphic_targets(klass, entry, eager_load: Associations.eager_load)
        end

        # Auto-built edges form a path of reflections (User#account ->
        # Account#owner -> ...). Re-encountering one means an insert cycle that
        # inverse_of cannot make persistable, so raise with the path and an
        # opt-out hint. A finite chain ended by a declaration never repeats an
        # edge and is allowed. Candidates are tried in the mapper's deterministic
        # order; the first one that bakes cleanly wins.
        def build_for_target(klass, entry, target_class)
          reuse = ReuseResolver.strategy_for(nil) == :reuse
          if reuse
            existing = resolve_reuse(klass, target_class, entry)
            return existing if existing
          end

          previous_path = reflection_path
          edge = "#{klass}##{entry.name}"
          ensure_acyclic!(previous_path, edge)

          Fiber[REFLECTION_PATH_KEY] = previous_path + [edge]
          with_suppressed(BackEdgeDetector.edges(target_class, klass, entry)) do
            bake_fresh(target_class, entry, reuse)
          end
        ensure
          Fiber[REFLECTION_PATH_KEY] = previous_path
        end

        # No candidates keeps the original actionable error, now naming the
        # sources that were tried. Candidates that all failed to bake report
        # what was attempted instead of hiding the cause.
        def raise_unresolved!(klass, entry, discovered, failures)
          name = entry.name
          hint = "Declare it (e.g. association :#{name}, factory: SomeClass) or pass #{name}: to name its target"
          if failures.empty?
            raise FactoryBakery::Error,
                  "#{klass}##{name} is a required polymorphic association; " \
                  "no target discovered from: #{discovered.sources.join('; ')}. #{hint}"
          end
          raise failures.first.last if failures.one?

          tried = failures.map { |target, error| "#{target} (#{error.class}: #{error.message})" }
          raise FactoryBakery::Error,
                "#{klass}##{name} is a required polymorphic association; " \
                "none of #{tried.join(', ')} could be baked. #{hint}"
        end

        def bake_fresh(target_class, entry, reuse)
          fresh = FkParentPersistence.persist!(FactoryBakery.bake(target_class), entry)
          ReuseResolver.remember(target_class, {}, entry, fresh) if reuse
          fresh
        end

        # An in-graph or database hit is reused as-is, except that an FK-presence
        # edge still gives it a real id before the owner validates. A miss
        # returns nil and the caller bakes a fresh parent, as it would without
        # a reuse strategy.
        def resolve_reuse(_klass, target_class, entry)
          existing = ReuseResolver.existing(target_class, {}, entry)
          FkParentPersistence.persist!(existing, entry) if existing
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
