# frozen_string_literal: true

module FactoryBakery
  module Sequel
    # The opt-in mapper for Sequel::Model classes: normalizes db_schema
    # columns, stored validations, association reflections and dataset
    # indexes into the framework-agnostic data the core consumes. Every
    # read of the source framework lives here or in the helper files beside
    # this one; nothing above the registry knows how the facts were
    # produced.
    class Mapper
      # Introspectable targets: Sequel::Model descendants only. Everything
      # else keeps the registry's empty defaults, and the default mapper
      # keeps its own world. The constant guard keeps this safe even when
      # this file is loaded while the ORM itself is still being defined.
      def supports?(klass)
        klass.is_a?(Class) && sequel_model?(klass)
      end

      # db_schema columns minus the primary key and guard columns: the
      # heuristics' candidate set. Guard columns (foreign keys of declared
      # many_to_one associations) can never be guessed, so they never enter
      # the universe at all.
      def attribute_universe(klass)
        guards = guard_columns(klass).names
        klass.db_schema.keys.map(&:to_s).reject { |name| guards.include?(name) }
      end

      # Normalized per-attribute constraints, memoized on the target class
      # like the default mapper does: a bake resolves the same pair many
      # times. Frozen targets are read without caching.
      def constraints_for(klass, attr_name)
        cache = cache_for(klass)
        return ConstraintReader.call(klass, attr_name.to_s) unless cache

        cache[attr_name.to_s] ||= ConstraintReader.call(klass, attr_name.to_s)
      end

      # Attributes heuristics must never fill: the primary key plus the
      # foreign keys of declared many_to_one associations (read from the
      # reflections; never auto-built). Counter names stay empty: Sequel
      # maintains no counter caches of its own.
      def guard_columns(klass)
        FactoryBakery::MapperRegistry::GuardColumns.new(
          names: guard_names(klass), counter_names: [].freeze
        )
      end

      # A many_to_one association name and its key columns form one alias
      # group; every member maps to the full set. Sequel has no polymorphic
      # pairing, so a group is exactly the association name plus its keys.
      def alias_groups(klass)
        many_to_one_reflections(klass).each_with_object({}) do |reflection, groups|
          members = [reflection[:name].to_s, *Array(reflection[:key]).map(&:to_s)]
          members.uniq!
          members.each { |member| groups[member] = members }
        end
      end

      def belongs_to_association_names(klass)
        many_to_one_reflections(klass).map { |reflection| reflection[:name].to_s }
      end

      # nil marks Sequel classes as not association-introspectable, which
      # the opt-in associations plugin distinguishes from "introspectable
      # with no associations" and answers with its clear "not supported"
      # error rather than guessing at Sequel edges.
      def association_introspection(_klass)
        nil
      end

      # Uniqueness comes from two sources: a stored uniqueness declaration
      # on the model, or a single-column unique index on the dataset
      # schema. Composite unique indexes constrain combinations, never a
      # single column, so they do not flag their members.
      def uniqueness_validated?(klass, attr_name)
        sequel_model?(klass) &&
          (uniqueness_reflection_names(klass) +
           unique_index_columns(klass)).include?(attr_name.to_s)
      end

      # Queries the model's own dataset: a value is taken when another row
      # holds it. The record itself is excluded so re-saving a persisted
      # value is not a collision, and nil is never taken (mirroring the
      # model-level validators, which skip nil).
      def uniqueness_check(record, attr_name, value)
        return false if value.nil?

        dataset = record.class.where(attr_name.to_sym => value)
        dataset = dataset.exclude(record.pk_hash) if !record.new? && record.pk_hash
        dataset.any?
      end

      # Human-readable descriptions for exhaustion errors, from the same
      # stored reflections the constraint reader folds.
      def validator_descriptions(klass, attr_name)
        return [] unless klass.respond_to?(:validation_reflections)

        Array(klass.validation_reflections[attr_name.to_sym])
          .map { |type, opts| ConstraintReader.describe_reflection(type, opts) }
      end

      # An imperative `validate` override is app logic the constraint reader
      # cannot see — validation_helpers' `validates_presence` lives there — so
      # a lean record must be verified. Stored declarations from
      # validation_class_methods are discoverable and need no probe: their
      # `validate` method is owned by the plugin module, not the model class.
      def custom_validation?(klass)
        return false unless sequel_model?(klass)

        klass.instance_method(:validate).owner == klass
      rescue NameError
        false
      end

      # Transactional semantics through the model's own database.
      def persistence_adapter(klass_or_record)
        subject = klass_or_record.is_a?(Class) ? klass_or_record : klass_or_record.class
        sequel_model?(subject) ? PersistenceAdapter : nil
      end

      private

      def sequel_model?(klass)
        return false unless defined?(::Sequel::Model)

        klass < ::Sequel::Model
      end

      def guard_names(klass)
        (Array(klass.primary_key).map(&:to_s) + association_key_names(klass)).uniq
      end

      # Foreign keys of declared many_to_one associations. A column that
      # merely ends in `_id` but backs no association stays fillable.
      def association_key_names(klass)
        many_to_one_reflections(klass).flat_map do |reflection|
          Array(reflection[:key]).map(&:to_s)
        end
      end

      # `Model.association_reflections` exists on every Sequel::Model class,
      # with or without declared associations.
      def many_to_one_reflections(klass)
        return [] unless klass.respond_to?(:association_reflections)

        klass.association_reflections.values.select { |reflection| reflection[:type] == :many_to_one }
      end

      # Stored uniqueness declarations for single attributes. Array keys
      # are grouped uniqueness (`validates_uniqueness_of [:a, :b]`) and are
      # skipped: a grouped constraint never makes one column alone unique.
      def uniqueness_reflection_names(klass)
        return [] unless klass.respond_to?(:validation_reflections)

        klass.validation_reflections
             .select do |att, entries|
               att.is_a?(Symbol) && entries.any? { |type, _opts| type == :uniqueness }
             end
             .keys.map(&:to_s)
      end

      # Single-column unique indexes on the model's dataset, memoized next
      # to the constraint cache: an index query per attribute per bake
      # would multiply schema round trips.
      def unique_index_columns(klass)
        cache = cache_for(klass)
        return unique_index_columns_uncached(klass) unless cache

        cache[:unique_index_columns] ||= unique_index_columns_uncached(klass)
      end

      def unique_index_columns_uncached(klass)
        klass.db.indexes(klass.table_name)
             .select { |_name, index| index[:unique] && index[:columns].length == 1 }
             .flat_map { |_name, index| index[:columns] }
             .map(&:to_s).uniq
      end

      # The per-class memo shared by constraints and index facts; nil for
      # frozen classes, which are read without caching (mirroring the
      # default mapper).
      def cache_for(klass)
        return nil if klass.frozen?

        klass.instance_variable_get(:@factory_bakery_sequel_cache) ||
          klass.instance_variable_set(:@factory_bakery_sequel_cache, {})
      end
    end
  end
end
