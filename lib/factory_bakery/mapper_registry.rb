# frozen_string_literal: true

module FactoryBakery
  # Registry of mapper plugins and the seam through which the
  # framework-agnostic core consumes one.
  #
  # A mapper normalizes ONE persistence/validation framework into the plain
  # data the core works with. The default mapper (under
  # FactoryBakery::ActiveRecordMapper) understands schema-backed models and
  # validator-bearing plain objects; further frameworks plug in the same way.
  #
  # Mapper protocol (every method takes the target class unless noted):
  #   supports?(klass)  => bool
  #       Can this mapper introspect the class at all?
  #   attribute_universe(klass) => [String]
  #       Attribute names heuristics may consider filling.
  #   constraints_for(klass, attr_name) => ConstraintSet
  #       The normalized description of one attribute.
  #   guard_columns(klass) => GuardColumns
  #       .names: attributes heuristics must never fill (foreign keys,
  #       polymorphic type columns, the STI discriminator, the primary key and
  #       framework-maintained counters).
  #       .counter_names: the counter subset (value-side logic fills NOT NULL
  #       counters without a default with 0).
  #   alias_groups(klass) => {String => [String]}
  #       Association name => [association name, *foreign key/type columns];
  #       every member maps to the full member set.
  #   belongs_to_association_names(klass) => [String]
  #       Which alias-group members are association names.
  #   association_introspection(klass) => [Association] or nil
  #       Plain descriptions of the class's associations, or nil when the
  #       class is not association-introspectable at all (a plain object, or
  #       a mapper that does not know associations). An introspectable class
  #       with no associations answers an empty array.
  #   polymorphic_targets(klass, entry, eager_load:) => DiscoveredTargets
  #       Ordered candidate classes and the discovery sources tried for a
  #       polymorphic belongs_to. Mappers without discovery may omit it.
  #   uniqueness_validated?(klass, attr_name) => bool
  #       Does the attribute carry a uniqueness constraint the mapper can
  #       check?
  #   save_validates_uniqueness?(klass, attr_name) => bool
  #       Does saving a record validate this attribute's uniqueness itself,
  #       unconditionally and with a `:taken` error naming the attribute? Then
  #       a `bake!` leaves a generated root value to its own save. Optional;
  #       the registry answers false.
  #   uniqueness_check(record, attr_name, value) => bool
  #       Is the value taken? (Only called when uniqueness_validated?.)
  #   uniqueness_case_insensitive?(klass, attr_name) => bool
  #       Does the attribute's uniqueness check fold case? Mappers without the
  #       notion may omit it (the registry answers false).
  #   validator_descriptions(klass, attr_name) => [String]
  #       Human-readable descriptions for exhaustion errors.
  #   persistence_adapter(klass_or_record) => adapter or nil
  #       Adapter methods: transactional?, transaction(klass) { }, save!(record),
  #       persisted?(record), association_name_for(record, candidates),
  #       read_only?(record).
  #   construct(klass, apply:) { } => object
  #       Builds an instance. The block is the ordinary construction
  #       (constructor arguments included) and is tried first; a mapper may
  #       retry with framework-specific strategies when it raises, and must
  #       re-raise the original error when none works. `apply` re-assigns the
  #       caller's constructor attributes to an object a fallback built without
  #       running the constructor.
  #
  # Targets no mapper claims fall back to empty answers, which reproduce the
  # pre-mapper duck-typed behavior exactly: an all-defaults ConstraintSet
  # (routing to a no-op), an empty universe, no guards, a null persistence
  # adapter, and the ordinary constructor.
  class MapperRegistry # rubocop:disable Metrics/ClassLength
    # Guard columns of one target: the skip set for heuristics plus the
    # counter subset the value side special-cases.
    GuardColumns = Struct.new(:names, :counter_names, keyword_init: true) do
      def self.none
        new(names: [].freeze, counter_names: [].freeze)
      end
    end

    # Plain description of one association on a mapped class. The fields are
    # framework-agnostic data; orchestration over them never touches the
    # source framework.
    #
    # `target`, `inverse_name` and `inverse_kind` are callables rather than
    # values: a target class and a verified inverse are resolved exactly when
    # the edge is actually used, so an unloadable sibling association or an
    # underivable inverse fails at that moment -- never while merely listing
    # a class's associations. Walkers that only probe an edge call `target`
    # directly and treat a failure as a conservative miss; call sites that
    # actually follow the edge call `resolve_target` so the failure surfaces
    # as a clear bake-time error naming the edge instead of a raw framework
    # error.
    Association = Struct.new(
      # String association name
      :name,
      # :belongs_to, :has_one, :has_many or :has_and_belongs_to_many
      :kind,
      # String target class name as declared, nil on a polymorphic edge
      :target_class_name,
      # [String] backing columns, composite allowed
      :foreign_keys,
      # String polymorphic type column, else nil
      :foreign_type,
      # Polymorphic edge?
      :polymorphic,
      # [String] counter-cache columns this association maintains on its owner
      :counter_cache_columns,
      # [String] the target attribute backing a natural key, nil for an id-keyed edge
      :natural_key_name,
      # Presence-validated or NOT NULL foreign key (belongs_to only)
      :required,
      # FK column itself carries a presence validator (non-polymorphic belongs_to only)
      :fk_presence,
      # Proc narrowing the edge, else nil
      :scope,
      # Join-backed edge (has_many/has_one :through)?
      :through,
      # Proc -> Class, resolved lazily
      :target,
      # Proc -> Symbol or nil, resolved lazily
      :inverse_name,
      # Proc -> Symbol or nil, resolved lazily
      :inverse_kind,
      # Proc -> (record) => bool: a presence validator on this association
      # whose if:/unless: conditions hold for the given record
      :presence_applicable
    ) do
      # Follow an edge. A target that cannot be resolved is an error at the
      # point of use, but it is reported with the association's name rather
      # than as the framework's raw exception. `target` itself is left intact
      # for conservative probes such as back-edge detection.
      def resolve_target
        target.call
      rescue FactoryBakery::Error
        raise
      rescue StandardError => e
        raise FactoryBakery::Error,
              "#{name} (target #{target_class_name.inspect}) could not be resolved: " \
              "#{e.class}: #{e.message}"
      end
    end

    # Ordered candidate classes for a polymorphic belongs_to plus the sources
    # discovery considered, for an actionable error when none can be baked.
    # Both fields are framework-agnostic data: plugin orchestration never
    # touches framework-specific reflection objects.
    DiscoveredTargets = Struct.new(:candidates, :sources, keyword_init: true) do
      def self.none
        new(candidates: [].freeze, sources: [].freeze)
      end
    end

    # The association list a mapper answers. It is an Array for the ordinary
    # contract, but also carries why any edge was skipped: a partially-loaded
    # class can list only its resolvable associations, and an explicit
    # reference to a dropped one needs a reason rather than a bare "missing".
    class Introspection < Array
      attr_reader :failures

      def initialize(entries = [], failures = {})
        super(entries)
        @failures = failures.dup.freeze
        freeze
      end

      # Failure for a named edge, or the class-wide failure when the whole
      # reflection set could not be built. nil when the edge is simply absent.
      def failure_for(name)
        @failures[name.to_s] || @failures[nil]
      end
    end

    # Duck-typed fallback for targets no mapper claims: builds never gain
    # transactional semantics, save! only runs when the target itself
    # implements it, and every record counts as persisted.
    class NullPersistenceAdapter
      def transactional?
        false
      end

      def transaction(_klass)
        yield
      end

      def save!(record)
        record.save! if record.respond_to?(:save!)
      end

      def persisted?(record)
        !record.respond_to?(:new_record?) || !record.new_record?
      end

      def association_name_for(_record, _candidates)
        nil
      end

      def read_only?(_record)
        false
      end
    end

    NULL_ADAPTER = NullPersistenceAdapter.new.freeze

    # Built-in mapper plugins shipped inside the gem, referenced by their
    # snake_case file names only: the core never spells a framework constant.
    DEFAULT_MAPPERS = %w[active_record_mapper].freeze

    class << self
      def register(mapper)
        return mapper if mappers.any? { |registered| registered.equal?(mapper) }

        @mappers = (mappers + [mapper]).freeze
        mapper
      end

      def mappers
        @mappers ||= [].freeze
      end

      def load_default_mappers
        DEFAULT_MAPPERS.each { |name| require_relative name }
      end

      # A bake asks for the same class's mapper dozens of times. The answer is
      # memoized on the class, tagged with the registry generation so a later
      # `register` invalidates it. Frozen classes are resolved every time.
      def mapper_for(klass)
        subject = klass.is_a?(Class) ? klass : klass.class
        return find_mapper(subject) if subject.frozen?

        generation, mapper = subject.instance_variable_get(:@factory_bakery_mapper)
        return mapper if generation == mappers.object_id

        mapper = find_mapper(subject)
        subject.instance_variable_set(:@factory_bakery_mapper, [mappers.object_id, mapper])
        mapper
      end

      def find_mapper(subject)
        mappers.find { |mapper| mapper.supports?(subject) }
      end
      private :find_mapper

      def constraints_for(klass, attr_name)
        mapper_for(klass)&.constraints_for(klass, attr_name.to_s) || ConstraintSet.empty(klass, attr_name.to_s)
      end

      # Whether an attribute's constraints can differ between records of the
      # same class (and so must not be served from a class-level cache while
      # a record is bound). Mappers without the notion answer false.
      def record_dependent?(klass, attr_name)
        mapper = mapper_for(klass)
        return false unless mapper.respond_to?(:record_dependent?)

        mapper.record_dependent?(klass, attr_name.to_s)
      end

      # True when the target has validation logic the heuristics cannot read
      # (custom validators, `validate` methods, `validates_with`). Those are
      # the cases where leaving an optional column unset could make a record
      # invalid for a reason no discovered constraint explains, so the core
      # verifies the lean result and falls back if needed. A mapper that does
      # not answer this question cannot promise its logic is discoverable, so
      # it defaults to "verify" rather than silently skipping the check.
      def custom_validation?(klass)
        mapper = mapper_for(klass)
        return true unless mapper.respond_to?(:custom_validation?)

        mapper.custom_validation?(klass)
      end

      def attribute_universe(klass)
        mapper_for(klass)&.attribute_universe(klass) || []
      end

      def guard_columns(klass)
        mapper_for(klass)&.guard_columns(klass) || GuardColumns.none
      end

      def alias_groups(klass)
        mapper_for(klass)&.alias_groups(klass) || {}
      end

      def belongs_to_association_names(klass)
        mapper_for(klass)&.belongs_to_association_names(klass) || []
      end

      # nil is meaningful here (unlike the other registry answers): it marks a
      # class no mapper can introspect associations for, which the plugins
      # distinguish from an introspectable class with no associations.
      def association_introspection(klass)
        mapper_for(klass)&.association_introspection(klass)
      end

      # Mappers that do not discover polymorphic targets simply contribute no
      # candidates; the plugin then raises its actionable error.
      def polymorphic_targets(klass, entry, eager_load: false)
        mapper = mapper_for(klass)
        return DiscoveredTargets.none unless mapper.respond_to?(:polymorphic_targets)

        mapper.polymorphic_targets(klass, entry, eager_load: eager_load)
      end

      def uniqueness_validated?(klass, attr_name)
        mapper_for(klass)&.uniqueness_validated?(klass, attr_name) || false
      end

      # Does saving a record validate this attribute's uniqueness itself, with
      # an error naming the attribute (`errors.details` kind `:taken`)? Then a
      # `bake!` can leave a generated value to its own save. A column guarded
      # only by a unique index raises from the database instead, so it is not
      # one. Mappers without the notion answer false.
      def save_validates_uniqueness?(klass, attr_name)
        mapper = mapper_for(klass)
        return false unless mapper.respond_to?(:save_validates_uniqueness?)

        mapper.save_validates_uniqueness?(klass, attr_name.to_s)
      end

      # Unique indexes as column-name arrays, composite included. Mappers that
      # do not model indexes answer no groups.
      def unique_index_groups(klass)
        mapper = mapper_for(klass)
        return [] unless mapper.respond_to?(:unique_index_groups)

        mapper.unique_index_groups(klass)
      end

      # Whether the attribute's uniqueness check folds case. Mappers without
      # the notion answer false; the core normalizes its per-bake collision
      # registry with it so two unsaved siblings cannot differ only by case.
      def uniqueness_case_insensitive?(klass, attr_name)
        mapper = mapper_for(klass)
        return false unless mapper.respond_to?(:uniqueness_case_insensitive?)

        mapper.uniqueness_case_insensitive?(klass, attr_name)
      end

      def uniqueness_check(record, attr_name, value)
        mapper_for(record)&.uniqueness_check(record, attr_name, value) || false
      end

      def validator_descriptions(klass, attr_name)
        mapper_for(klass)&.validator_descriptions(klass, attr_name) || []
      end

      def persistence_adapter(klass_or_record)
        mapper_for(klass_or_record)&.persistence_adapter(klass_or_record) || NULL_ADAPTER
      end

      # Whether the record refuses writes (a database view, or any model whose
      # readonly? is true). Asked on the instance so instance-level read-only
      # records are caught too. The adapters own the framework-specific read.
      def read_only?(record) = persistence_adapter(record).read_only?(record)

      # Whether the target's table exposes `attribute` as a column. Mappers
      # without the notion answer true, so a core caller never loses a build
      # over a column it cannot rule out.
      def column?(klass, attr_name)
        mapper = mapper_for(klass)
        return true unless mapper.respond_to?(:column?)

        mapper.column?(klass, attr_name.to_s)
      end

      # Whether a text attribute must hold a JSON document: the target's own
      # type is text, but a table index casts it to json/jsonb (PostgreSQL
      # expression indexes). The value side reads this fact to emit parseable
      # JSON. Mappers without the notion answer false.
      def json_text?(klass, attr_name)
        mapper = mapper_for(klass)
        return false unless mapper.respond_to?(:json_text?)

        mapper.json_text?(klass, attr_name.to_s)
      end

      # Builds an instance of the target. The block is the ordinary
      # construction and is always tried first; a mapper that knows how to
      # recover from a raising constructor answers with its own fallbacks.
      def construct(klass, apply: nil, &block)
        mapper = mapper_for(klass)
        mapper.respond_to?(:construct) ? mapper.construct(klass, apply: apply, &block) : yield
      end
    end
  end
end
