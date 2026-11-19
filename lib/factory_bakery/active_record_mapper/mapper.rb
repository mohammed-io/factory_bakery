# frozen_string_literal: true

module FactoryBakery
  module ActiveRecordMapper
    # The default mapper: normalizes schema-backed (ActiveRecord) models and
    # validator-bearing plain objects into the framework-agnostic data the
    # core consumes. Every read of the source framework lives here or in the
    # helper files beside this one; nothing above the registry knows how the
    # facts were produced.
    class Mapper
      # Introspectable targets: anything schema-backed or anything that
      # declares ActiveModel-style validators. Plain targets that expose
      # neither stay unmapped and keep the registry's empty defaults.
      def supports?(klass)
        klass.respond_to?(:columns_hash) || klass.respond_to?(:validators_on)
      end

      # Schema-backed targets enumerate their columns. Validator-bearing
      # targets have no schema, so the only attributes that can carry
      # heuristic information are the ones their validators declare.
      def attribute_universe(klass)
        return klass.columns_hash.keys.map(&:to_s) if klass.respond_to?(:columns_hash)

        validator_attribute_names(klass)
      end

      # Normalized per-attribute constraints, memoized on the target class:
      # a bake resolves the same pair many times (routing, generation,
      # counter handling, uniqueness regeneration). Reloading a class drops
      # its cache with it. Frozen targets are read without caching, matching
      # the fillers' own frozen-class handling.
      def constraints_for(klass, attr_name)
        cache = cache_for(klass)
        return ConstraintReader.call(klass, attr_name.to_s) unless cache

        cache[attr_name.to_s] ||= ConstraintReader.call(klass, attr_name.to_s)
      end

      # Attributes heuristics must never fill: foreign keys, polymorphic
      # type columns, the STI discriminator, the primary key and
      # framework-maintained counters. Counter names are reported separately
      # because the value side fills a NOT NULL counter without a default
      # with 0 instead of leaving it untouched.
      def guard_columns(klass)
        FactoryBakery::MapperRegistry::GuardColumns.new(
          names: guard_names(klass), counter_names: counter_names(klass)
        )
      end

      # An association name and the columns backing it (the FK, plus the type
      # column for a polymorphic association) form one alias group; every
      # member maps to the full set. The association name is always first.
      def alias_groups(klass)
        return {} unless klass.respond_to?(:reflect_on_all_associations)

        ReflectionCache.belongs_to(klass).each_with_object({}) do |reflection, groups|
          members = [reflection.name.to_s, *Array(reflection.foreign_key).map(&:to_s)]
          members << reflection.foreign_type.to_s if reflection.polymorphic?
          members.uniq!
          members.each { |member| groups[member] = members }
        end
      end

      def belongs_to_association_names(klass)
        return [] unless klass.respond_to?(:reflect_on_all_associations)

        ReflectionCache.belongs_to(klass).map { |reflection| reflection.name.to_s }
      end

      # Uniqueness is delegated to the model's own uniqueness validator, so
      # scoping, case sensitivity, conditions, enum mapping and STI finder
      # resolution behave exactly as they do during a real save.
      def uniqueness_validated?(klass, attr_name)
        return false unless active_record_class?(klass)
        return false unless klass.respond_to?(:validators_on)

        klass.validators_on(attr_name).any? do |validator|
          validator.is_a?(::ActiveRecord::Validations::UniquenessValidator)
        end
      end

      # Runs the real validator against a throwaway copy of the record so its
      # errors are not mixed into the object the caller receives.
      def uniqueness_check(record, attr_name, value)
        uniqueness_validated?(record.class, attr_name) &&
          uniqueness_validators_for(record.class, attr_name).any? do |validator|
            probe = build_probe(record, attr_name, value)
            validator.validate_each(probe, attr_name, value)
            taken_error?(probe.errors, attr_name)
          end
      end

      # Human-readable validator descriptions for exhaustion errors.
      def validator_descriptions(klass, attr_name)
        return [] unless klass.respond_to?(:validators_on)

        klass.validators_on(attr_name).map { |validator| describe_validator(validator) }
      end

      # Transactional semantics for targets that open transactions
      # (savepoints when the caller already holds a transaction).
      def persistence_adapter(klass_or_record)
        subject = klass_or_record.is_a?(Class) ? klass_or_record : klass_or_record.class
        subject.respond_to?(:transaction) ? PersistenceAdapter : nil
      end

      private

      def guard_names(klass)
        names = belongs_to_guard_names(klass)
        names.concat(counter_names(klass))
        names << sti_discriminator_name(klass)
        names << primary_key_name(klass)
        names.compact.uniq
      end

      def counter_names(klass)
        CounterCacheDetector.new(klass).column_names
      end

      # Columns behind a belongs_to cannot be guessed: a random FK dangles
      # against a real DB constraint, and a random polymorphic type is not a
      # constant. `foreign_key` is an array for composite FKs and a string
      # otherwise.
      def belongs_to_guard_names(klass)
        return [] unless klass.respond_to?(:columns_hash) && klass.respond_to?(:reflect_on_all_associations)

        ReflectionCache.belongs_to(klass).flat_map do |reflection|
          names = Array(reflection.foreign_key).map(&:to_s)
          names << reflection.foreign_type.to_s if reflection.polymorphic?
          names
        end
      end

      # The STI discriminator is assigned by the framework's `new`; a faked
      # value would make a persisted row unloadable. Disabling STI empties
      # the column name, so a plain `type` column stays guard-free.
      def sti_discriminator_name(klass)
        return nil unless klass.respond_to?(:inheritance_column)

        column = klass.inheritance_column
        column.to_s.empty? ? nil : column.to_s
      end

      def primary_key_name(klass)
        return nil unless klass.respond_to?(:columns_hash)

        klass.primary_key.to_s
      end

      def validator_attribute_names(klass)
        return [] unless klass.respond_to?(:validators)

        klass.validators.flat_map do |validator|
          names = Array(validator.attributes).map(&:to_s)
          if validator.class.name == 'ActiveModel::Validations::ConfirmationValidator'
            names + names.map { |name| "#{name}_confirmation" }
          else
            names
          end
        end.uniq
      end

      def active_record_class?(klass)
        defined?(::ActiveRecord::Base) && klass < ::ActiveRecord::Base
      end

      def uniqueness_validators_for(klass, attr_name)
        klass.validators_on(attr_name).select do |validator|
          validator.is_a?(::ActiveRecord::Validations::UniquenessValidator)
        end
      end

      def build_probe(record, attr_name, value)
        probe = record.dup
        probe.public_send("#{attr_name}=", value) if probe.respond_to?("#{attr_name}=")
        probe.errors.clear if probe.respond_to?(:errors)
        probe
      end

      # `Errors#added?` does a strict options match, but the uniqueness
      # validator attaches the candidate as `value:`. `details` keeps just
      # the error kind.
      def taken_error?(errors, attr_name)
        details = errors.details[attr_name.to_sym] || errors.details[attr_name.to_s]
        Array(details).any? { |detail| detail[:error] == :taken }
      end

      def describe_validator(validator)
        name = validator.class.name.to_s.split('::').last.to_s.sub(/Validator\z/, '')
        ignored = %i[if unless on class allow_nil allow_blank message]
        options = validator.options.reject { |key, _| ignored.include?(key) }
        options = options.transform_values { |value| value.is_a?(Proc) ? '<callable>' : value }
        options.empty? ? name : "#{name}: #{options.inspect}"
      end

      def cache_for(klass)
        return nil if klass.frozen?

        klass.instance_variable_get(:@factory_bakery_constraints) ||
          klass.instance_variable_set(:@factory_bakery_constraints, {})
      end
    end
  end
end
