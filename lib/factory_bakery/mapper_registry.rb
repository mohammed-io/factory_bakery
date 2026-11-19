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
  #   supported?(klass)  => bool
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
  #   uniqueness_validated?(klass, attr_name) => bool
  #       Does the attribute carry a uniqueness constraint the mapper can
  #       check?
  #   uniqueness_check(record, attr_name, value) => bool
  #       Is the value taken? (Only called when uniqueness_validated?.)
  #   validator_descriptions(klass, attr_name) => [String]
  #       Human-readable descriptions for exhaustion errors.
  #   persistence_adapter(klass_or_record) => adapter or nil
  #       Adapter methods: transactional?, transaction(klass) { }, save!(record),
  #       persisted?(record), association_name_for(record, candidates).
  #
  # Targets no mapper claims fall back to empty answers, which reproduce the
  # pre-mapper duck-typed behavior exactly: an all-defaults ConstraintSet
  # (routing to a no-op), an empty universe, no guards, and a null
  # persistence adapter.
  class MapperRegistry
    # Guard columns of one target: the skip set for heuristics plus the
    # counter subset the value side special-cases.
    GuardColumns = Struct.new(:names, :counter_names, keyword_init: true) do
      def self.none
        new(names: [].freeze, counter_names: [].freeze)
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

      def mapper_for(klass)
        subject = klass.is_a?(Class) ? klass : klass.class
        mappers.find { |mapper| mapper.supports?(subject) }
      end

      def constraints_for(klass, attr_name)
        mapper_for(klass)&.constraints_for(klass, attr_name.to_s) ||
          ConstraintSet.empty(klass, attr_name.to_s)
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

      def uniqueness_validated?(klass, attr_name)
        mapper_for(klass)&.uniqueness_validated?(klass, attr_name) || false
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
    end
  end
end
