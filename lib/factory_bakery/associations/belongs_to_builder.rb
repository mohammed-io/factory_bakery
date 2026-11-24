# frozen_string_literal: true

require_relative '../fiber_local'

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
            next if skip_automatic_edge?(klass, entry, taken)

            key, value = build_automatic_value(klass, entry, values.values)
            next if value.nil? && optional_edge?(entry)

            values[key] = value
          end
        end

        # `siblings` are the parents already chosen for this same owner. Two
        # edges of one record (Transfer#sender / #receiver) never share an
        # object: apps routinely require them to differ.
        def build_value(klass, entry, siblings)
          parent = build_parent(klass, entry, siblings)
          return [entry.name, parent] unless column_fk?(klass, entry)

          persist_column_fk!(parent) if parent
          [entry.foreign_keys.first, parent.respond_to?(:id) ? parent.id : nil]
        end

        # True for a collection on `klass` that points back to the class whose
        # belongs_to we just followed. :all uses this to skip the return edge.
        def suppressed_edge?(klass, entry_name)
          suppressed_edges.include?([klass.name, entry_name.to_s])
        end

        private

        def build_automatic_value(klass, entry, siblings)
          return build_value(klass, entry, siblings) unless BuildContext.persisting? && Associations.mode == :all

          mark = BuildContext.generated_records.length
          key, value = build_value(klass, entry, siblings)
          BuildContext.record_automatic_parent(BuildContext.current_record, entry, value, mark)
          [key, value]
        end

        def auto_building?
          %i[required_only all].include?(Associations.mode)
        end

        def entries_to_build(introspection, context)
          belongs_to = introspection.select { |entry| id_keyed_belongs_to?(entry) }
          entries = mode_entries(belongs_to, context)
          entries = without_competing_writers(entries) if Associations.mode == :all
          (entries + error_directed(belongs_to, entries)).map { |entry| fk_blamed(entry) }
        end

        # A selected polymorphic edge owns the FK/type pair. An optional
        # unscoped typed writer would either duplicate that target or overwrite
        # its ID without updating the type. Required/scoped typed edges have
        # their own contract, and an unselected polymorphic edge owns no key.
        def without_competing_writers(entries)
          polymorphic_keys = entries.select(&:polymorphic).map { |entry| entry.foreign_keys.sort }
          entries.reject do |entry|
            !entry.polymorphic && !entry.scope && !entry.fk_presence &&
              !presence_applies?(entry) &&
              polymorphic_keys.include?(entry.foreign_keys.sort)
          end
        end

        # A conditional validator may not be evaluable here (no record yet);
        # treat it as applying so the typed edge is kept, not dropped.
        def presence_applies?(entry)
          entry.presence_applicable.call(BuildContext.current_record)
        rescue StandardError
          true
        end

        def mode_entries(belongs_to, context)
          return belongs_to.select(&:required) unless Associations.mode == :all && !Associations.past_depth?(context)

          belongs_to.select { |entry| !entry.polymorphic || entry.required }
        end

        # A verified-fallback rebuild knows which attributes the lean probe
        # blamed. An optional belongs_to among them is built like a required
        # edge: a custom validator (Discourse's `PostValidator` adding
        # "Topic can't be blank" on an optional association) demands it even
        # though no discovered constraint does. The names are scoped to the
        # one record being rebuilt (FillOptional), so a nested bake is
        # unaffected.
        def error_directed(belongs_to, already)
          names = FactoryBakery::FillOptional.rebuild_error_attributes
          return [] if names.empty?

          belongs_to.reject { |entry| already.include?(entry) }.select do |entry|
            [entry.name, *entry.foreign_keys].any? { |name| names.include?(name.to_s) }
          end
        end

        # A validator that blamed the foreign key column reads the id, which an
        # unsaved parent does not have until autosave runs after validation.
        # Such an edge (whether the rebuild added it or was building it anyway)
        # is treated as an FK-presence edge, so its parent is inserted first
        # exactly like one guarded by `validates :x_id, presence: true`.
        def fk_blamed(entry)
          names = FactoryBakery::FillOptional.rebuild_error_attributes
          return entry if entry.fk_presence
          return entry unless entry.foreign_keys.any? { |key| names.include?(key.to_s) }

          entry.dup.tap { |fk_edge| fk_edge.fk_presence = true }
        end

        # Natural keys are handled after instantiation by NaturalKeyBuilder,
        # once the child's own key value is known.
        def id_keyed_belongs_to?(entry)
          entry.kind == :belongs_to && entry.natural_key_name.nil?
        end

        def skip_automatic_edge?(klass, entry, taken)
          return true if alias_members(entry).any? { |name| taken.include?(name) }

          optional_edge?(entry) && entry.foreign_keys.any? { |key| !FactoryBakery::MapperRegistry.column?(klass, key) }
        end

        def alias_members(entry)
          names = [entry.name, *entry.foreign_keys]
          names << entry.foreign_type if entry.polymorphic
          names.uniq
        end

        # A polymorphic edge asks the mapper for candidate classes; an ordinary
        # one resolves its target directly. Both arrive as plain data.
        #
        # :all shares the dependency graph: a completed object of exactly the
        # target class is reused instead of built again (unless the edge is
        # scoped or its foreign key is uniqueness-validated, where sharing
        # would violate the constraint). Under `bake!` only a persisted object
        # is shared, because an unsaved parent in a graph about to be inserted
        # can close a cycle through Rails' autosave. An optional edge is built
        # in a savepoint and discarded, nil, when its child raises or is
        # invalid; a required edge keeps the old behaviour of surfacing the
        # failure.
        def build_parent(klass, entry, siblings = [])
          return build_optional_parent(klass, entry, siblings) if optional_edge?(entry)

          completed_parent(klass, entry, siblings) || build_required_parent(klass, entry)
        end

        def completed_parent(klass, entry, siblings)
          return nil if entry.polymorphic
          return nil unless ReuseResolver.strategy_for(nil) == :fresh
          return nil if entry.scope
          return nil if uniqueness_validated_fk?(klass, entry)

          shareable(BuildContext.completed_object_of(entry.resolve_target, exclude: siblings), entry)
        end

        # A raw-FK-presence edge needs a real id on the owner, so only an
        # already persisted object can be shared there; an unsaved one is
        # left alone and the edge builds (and inserts) its own parent. Under
        # `bake!` (`BuildContext.persisting?`) the same rule holds for every
        # edge: sharing an unsaved parent across a graph that is about to be
        # inserted makes Rails' autosave walk a cycle (a new parent whose
        # collection reaches the child being saved) and can insert the child
        # with a nil foreign key. A persisted object is safe to share.
        def shareable(object, entry)
          return nil unless object
          return object unless entry.fk_presence || BuildContext.persisting?

          object.respond_to?(:persisted?) && object.persisted? ? object : nil
        end

        def uniqueness_validated_fk?(klass, entry)
          entry.foreign_keys.any? do |key|
            FactoryBakery::MapperRegistry.uniqueness_validated?(klass, key)
          end
        end

        def optional_edge?(entry)
          Associations.mode == :all && !entry.required
        end

        # A candidate that fails is discarded whole: its savepoint rolls back
        # any row its FK-presence parent inserted, and the generated-record
        # mark drops the records it built so `bake!` verifies only the graph
        # that was kept (otherwise a failed candidate's unsaved parent fails
        # the winning bake).
        def build_required_parent(klass, entry)
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

        def build_optional_parent(klass, entry, siblings)
          mark = BuildContext.generated_records.length
          completed = completed_parent(klass, entry, siblings)
          return completed if completed

          adapter = FactoryBakery::MapperRegistry.persistence_adapter(klass)
          return optional_candidate(klass, entry) unless adapter.transactional?

          adapter.transaction(klass) { optional_candidate(klass, entry) }
        rescue StandardError
          BuildContext.trim_generated_records!(mark)
          nil
        end

        def optional_candidate(klass, entry)
          parent = build_required_parent(klass, entry)
          persist_column_fk!(parent) if column_fk?(klass, entry)
          raise FactoryBakery::FallbackBuilder::DiscardAttempt if invalid_child?(parent)

          parent
        end

        # A child whose validation raises cannot certify itself either, so it
        # counts as invalid and the optional edge is dropped. Its unsaved
        # required parents must be valid too (GraphValidity).
        def invalid_child?(child)
          GraphValidity.invalid?(child)
        end

        # Rails' anonymous HABTM join model declares `belongs_to :left_side`
        # without a real foreign key. The join table's actual left column is
        # the owner model's foreign key, exposed by the mapper as the entry's
        # foreign key. Assign that column's id instead of the synthetic
        # association writer (which does not exist on the join table).
        def column_fk?(klass, entry)
          entry.name == 'left_side' && klass.name.to_s.split('::').last.to_s.start_with?('HABTM_')
        end

        # A read-only parent is never saved, even here.
        def persist_column_fk!(parent)
          return unless BuildContext.persisting?
          return unless parent.respond_to?(:new_record?) && parent.new_record?
          return if FactoryBakery::MapperRegistry.read_only?(parent)

          FactoryBakery::MapperRegistry.persistence_adapter(parent).save!(parent)
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
          reuse = ReuseResolver.reuse?(klass, nil, entry)
          if reuse
            existing = resolve_reuse(klass, target_class, entry)
            return existing if existing
          end

          previous_path = reflection_path
          edge = "#{klass}##{entry.name}"
          return nil if skip_optional_cycle?(previous_path, edge, target_class, entry)

          ensure_acyclic!(previous_path, edge)

          FactoryBakery::FiberLocal[REFLECTION_PATH_KEY] = previous_path + [edge]
          with_suppressed(BackEdgeDetector.edges(target_class, klass, entry)) do
            bake_fresh(target_class, entry, reuse)
          end
        ensure
          FactoryBakery::FiberLocal[REFLECTION_PATH_KEY] = previous_path
        end

        # Only a required edge may close a cycle. An optional edge that would
        # repeat its reflection path, or point at a class already being built
        # (an optional self-reference such as Status#quoted_status), is
        # skipped and stays nil instead of recursing.
        def skip_optional_cycle?(path, edge, target_class, entry)
          return false if entry.required
          return false unless Associations.mode == :all

          path.include?(edge) || BuildContext.current.path.include?(target_class)
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
          fresh = FkParentPersistence.build(BuildContext.current_record, entry, transaction_class: target_class) do
            BuildContext.automatic_build { FactoryBakery.bake(target_class) }
          end
          ReuseResolver.remember(target_class, {}, entry, fresh) if reuse
          fresh
        end

        # An in-graph or database hit is reused as-is, except that an FK-presence
        # edge still gives it a real id before the owner validates and a
        # read-only parent is settled exactly like a fresh one. A miss returns
        # nil and the caller bakes a fresh parent, as it would without a
        # reuse_non_unique strategy.
        def resolve_reuse(_klass, target_class, entry)
          existing = ReuseResolver.existing(target_class, {}, entry)
          FkParentPersistence.settle(existing, BuildContext.current_record, entry) if existing
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
          FactoryBakery::FiberLocal[SUPPRESSED_EDGES_KEY] = (previous + edges).uniq.freeze
          yield
        ensure
          FactoryBakery::FiberLocal[SUPPRESSED_EDGES_KEY] = previous
        end

        def suppressed_edges
          FactoryBakery::FiberLocal[SUPPRESSED_EDGES_KEY] ||= [].freeze
        end

        def reflection_path
          FactoryBakery::FiberLocal[REFLECTION_PATH_KEY] ||= [].freeze
        end
      end
    end
  end
end
