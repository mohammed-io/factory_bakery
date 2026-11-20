# frozen_string_literal: true

module FactoryBakery
  module ActiveRecordMapper
    # The default mapper: normalizes schema-backed (ActiveRecord) models and
    # validator-bearing plain objects into the framework-agnostic data the
    # core consumes. Every read of the source framework lives here or in the
    # helper files beside this one; nothing above the registry knows how the
    # facts were produced.
    class Mapper
      # Validators whose rules are fully discoverable as constraints. Any
      # other validator (a custom EachValidator, validates_with, or a
      # `validate` method) may depend on a column we deliberately left unset.
      DISCOVERABLE_VALIDATORS = %w[
        ActiveModel::Validations::PresenceValidator
        ActiveModel::Validations::AbsenceValidator
        ActiveModel::Validations::FormatValidator
        ActiveModel::Validations::LengthValidator
        ActiveModel::Validations::InclusionValidator
        ActiveModel::Validations::ExclusionValidator
        ActiveModel::Validations::NumericalityValidator
        ActiveModel::Validations::AcceptanceValidator
        ActiveModel::Validations::ConfirmationValidator
        ActiveModel::Validations::ComparisonValidator
        ActiveRecord::Validations::PresenceValidator
        ActiveRecord::Validations::LengthValidator
        ActiveRecord::Validations::NumericalityValidator
        ActiveRecord::Validations::UniquenessValidator
        ActiveRecord::Validations::AcceptanceValidator
      ].freeze

      # Framework-owned callbacks that are not app validation logic and must
      # not force a verification pass. Autosave registers one
      # `validate_associated_records_for_*` callback per association, so a
      # plain has_many would otherwise make nearly every model look custom.
      INTERNAL_VALIDATE_CALLBACKS = %i[cant_modify_encrypted_attributes_when_frozen].freeze
      AUTOSAVE_VALIDATE_CALLBACK_PREFIX = 'validate_associated_records_for_'

      # Introspectable targets: anything schema-backed or anything that
      # declares ActiveModel-style validators. Plain targets that expose
      # neither stay unmapped and keep the registry's empty defaults.
      def supports?(klass)
        klass.respond_to?(:columns_hash) || klass.respond_to?(:validators_on)
      end

      # Schema-backed targets enumerate their columns plus the virtual
      # attributes their validators declare, because a validated `password` or
      # `terms_of_service` is as necessary to a valid record as any column
      # (issue #57). Validator-bearing targets without a schema have no
      # columns, so their validator-declared names are the whole universe.
      # Memoized on the class like the constraints: computing the virtual
      # names walks validators, reflections and guard columns, which every
      # bake would otherwise repeat.
      def attribute_universe(klass)
        class_memo(klass, :@factory_bakery_universe) { compute_attribute_universe(klass).freeze }
      end

      # Class-level introspection facts are stable for a loaded class, so they
      # are computed once and kept on the class (a reload drops them with it).
      # Frozen classes are recomputed every time.
      def class_memo(klass, ivar)
        return yield if klass.frozen?

        klass.instance_variable_get(ivar) || klass.instance_variable_set(ivar, yield)
      end
      private :class_memo

      def compute_attribute_universe(klass)
        columns = klass.respond_to?(:columns_hash) ? klass.columns_hash.keys.map(&:to_s) : []
        return columns unless klass.respond_to?(:validators)

        (columns + virtual_attribute_names(klass)).uniq
      end
      private :compute_attribute_universe

      # Normalized per-attribute constraints, memoized on the target class:
      # a bake resolves the same pair many times (routing, generation,
      # counter handling, uniqueness regeneration). Reloading a class drops
      # its cache with it. Frozen targets are read without caching, matching
      # the fillers' own frozen-class handling.
      #
      # While a matching record is being filled, rules that depend on live
      # state must be resolved against it, so the class-level cache is skipped
      # and the reader evaluates those rules for this record only. Attributes
      # without conditional rules keep using the cache.
      def constraints_for(klass, attr_name)
        record = BuildContext.current_record
        if record.is_a?(klass) && record_dependent?(klass, attr_name)
          return ConstraintReader.call(klass, attr_name.to_s, record)
        end

        cache = cache_for(klass)
        return ConstraintReader.call(klass, attr_name.to_s) unless cache

        cache[attr_name.to_s] ||= ConstraintReader.call(klass, attr_name.to_s)
      end

      # True when a validator on the attribute (or on its confirmation source)
      # carries if:/unless:, so its constraints can differ from record to
      # record. Memoized per class like the constraints themselves.
      def record_dependent?(klass, attr_name)
        return false unless klass.respond_to?(:validators_on)

        name = attr_name.to_s
        memo = cache_for(klass) && (klass.instance_variable_get(:@factory_bakery_record_dependent) ||
                                    klass.instance_variable_set(:@factory_bakery_record_dependent, {}))
        return conditional_validators?(klass, name) unless memo
        return memo[name] if memo.key?(name)

        memo[name] = conditional_validators?(klass, name)
      end

      # App-supplied validation cannot be read as constraints, so the core
      # cannot know that an optional column matters to it. Reading the real
      # callback chain keeps this inside the mapper. Framework-owned callbacks
      # (encrypted-attribute guards and autosave's association validators) are
      # not app logic: a plain has_many must not add a verification pass.
      def custom_validation?(klass)
        return false unless klass.respond_to?(:_validate_callbacks)

        klass._validate_callbacks.any? do |callback|
          filter = callback.filter
          next false if internal_validate_callback?(filter)
          next true unless defined?(::ActiveModel::Validator) && filter.is_a?(::ActiveModel::Validator)

          !DISCOVERABLE_VALIDATORS.include?(filter.class.name)
        end
      end

      # Attributes heuristics must never fill: foreign keys, polymorphic
      # type columns, the STI discriminator, the primary key and
      # framework-maintained counters. Counter names are reported separately
      # because the value side fills a NOT NULL counter without a default
      # with 0 instead of leaving it untouched.
      def guard_columns(klass)
        class_memo(klass, :@factory_bakery_guard_columns) do
          FactoryBakery::MapperRegistry::GuardColumns.new(
            names: guard_names(klass).freeze, counter_names: counter_names(klass).freeze
          )
        end
      end

      # An association name and the columns backing it (the FK, plus the type
      # column for a polymorphic association) form one alias group; every
      # member maps to the full set. The association name is always first.
      # `alias_attribute` names group with their column the same way, so the
      # alias and its column are decided once (issue #61).
      def alias_groups(klass)
        class_memo(klass, :@factory_bakery_alias_groups) do
          groups = association_alias_groups(klass)
          attribute_alias_groups(klass).each do |members|
            next if members.any? { |member| groups.key?(member) }

            members.each { |member| groups[member] = members }
          end
          groups.transform_values(&:freeze).freeze
        end
      end

      def belongs_to_association_names(klass)
        return [] unless klass.respond_to?(:reflect_on_all_associations)

        ReflectionCache.belongs_to(klass).map { |reflection| reflection.name.to_s }
      end

      # Plain per-association data for the associations orchestration, or nil
      # when the class is not association-introspectable at all (see
      # AssociationIntrospection, which builds and caches the entries).
      def association_introspection(klass)
        AssociationIntrospection.for(klass)
      end

      # Ordered candidate classes for a polymorphic belongs_to, plus the
      # discovery sources tried. The framework reads live in the helper, so
      # the plugin never sees a reflection or a Rails constant (ADR-0001).
      def polymorphic_targets(klass, entry, eager_load: false)
        PolymorphicTargetDiscovery.call(klass, entry, eager_load: eager_load)
      end

      # Uniqueness is delegated to the model's own uniqueness validator, so
      # scoping, case sensitivity, conditions, enum mapping and STI finder
      # resolution behave exactly as they do during a real save. A database
      # that rejects a duplicate through a single-column unique index instead
      # of a validator is just as binding, so such a column is flagged too and
      # the core keeps it unique across the unsaved siblings of one bake.
      def uniqueness_validated?(klass, attr_name)
        return false unless active_record_class?(klass)
        return false unless klass.respond_to?(:validators_on)

        uniqueness_validator?(klass, attr_name) ||
          unique_index_columns(klass).include?(attr_name.to_s)
      end

      # A `case_sensitive: false` uniqueness validator treats "Token" and
      # "token" as one value. The core normalizes the values in its per-bake
      # collision registry with this, so two unsaved siblings collide the way
      # the database would.
      def uniqueness_case_insensitive?(klass, attr_name)
        return false unless klass.respond_to?(:validators_on)

        uniqueness_validators_for(klass, attr_name).any? do |validator|
          validator.options[:case_sensitive] == false
        end
      end

      # Runs the real validator against a throwaway copy of the record so its
      # errors are not mixed into the object the caller receives. A column
      # protected only by a single-column UNIQUE index has no validator, so the
      # database is asked directly for it: such an index is just as binding as
      # a `validates ... uniqueness:` rule.
      def uniqueness_check(record, attr_name, value)
        return false unless uniqueness_validated?(record.class, attr_name)

        validators = uniqueness_validators_for(record.class, attr_name)
        return unique_index_taken?(record, attr_name, value) if validators.empty?

        validators.any? do |validator|
          probe = build_probe(record, attr_name, value)
          validator.validate_each(probe, attr_name, value)
          taken_error?(probe.errors, attr_name)
        end
      end

      # Does the database already hold `value` in a unique-indexed column? The
      # record's own class scopes the query like the index's table (default
      # scope and STI included); a persisted record never collides with itself.
      def unique_index_taken?(record, attr_name, value)
        klass = record.class
        return false if value.nil?
        return false unless klass.respond_to?(:where)

        # `unscoped` matches the database index (and Rails' own uniqueness
        # validator) instead of a default scope that could hide a row.
        scope = klass.respond_to?(:unscoped) ? klass.unscoped : klass
        scope = scope.where(attr_name => value)
        if record.respond_to?(:persisted?) && record.persisted? && klass.primary_key
          scope = scope.where.not(klass.primary_key => record.public_send(klass.primary_key))
        end
        scope.exists?
      rescue StandardError
        false
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

      # Builds an instance, retrying through the framework's construction
      # fallbacks when the ordinary constructor raises (issue #56). `apply`
      # assigns the caller's constructor attributes to an object a fallback
      # built without running the constructor.
      def construct(klass, apply: nil, &block)
        Construction.call(klass, apply: apply, &block)
      end

      private

      # Autosave callbacks are installed by the framework for every
      # association; their `validate_associated_records_for_<name>` names are
      # implementation details, not validations the core needs to probe.
      def internal_validate_callback?(filter)
        return true if INTERNAL_VALIDATE_CALLBACKS.include?(filter)

        name = filter.is_a?(Symbol) || filter.is_a?(String) ? filter.to_s : ''
        name.start_with?(AUTOSAVE_VALIDATE_CALLBACK_PREFIX)
      end

      def association_alias_groups(klass)
        return {} unless klass.respond_to?(:reflect_on_all_associations)

        ReflectionCache.belongs_to(klass).each_with_object({}) do |reflection, groups|
          members = [reflection.name.to_s, *Array(reflection.foreign_key).map(&:to_s)]
          members << reflection.foreign_type.to_s if reflection.polymorphic?
          members.uniq!
          members.each { |member| groups[member] = members }
        end
      end

      # Each `alias_attribute` name is a second spelling of a column, so both
      # names belong to one group. A name already grouped by an association
      # keeps its association group.
      def attribute_alias_groups(klass)
        return [] unless klass.respond_to?(:attribute_aliases) && klass.respond_to?(:columns_hash)

        klass.attribute_aliases.filter_map do |alias_name, column|
          [alias_name.to_s, column.to_s] if klass.columns_hash.key?(column.to_s)
        end
      end

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
      # otherwise. A natural key (issue #54) is the exception: its FK is a real
      # data column (for example `domain`) that heuristics can fill, so it is
      # deliberately left unguarded.
      def belongs_to_guard_names(klass)
        return [] unless klass.respond_to?(:columns_hash) && klass.respond_to?(:reflect_on_all_associations)

        ReflectionCache.belongs_to(klass).flat_map do |reflection|
          next [] if NaturalKey.natural?(reflection)

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
          # A `validates_with` validator names no attributes.
          names = validator.respond_to?(:attributes) ? Array(validator.attributes).map(&:to_s) : []
          if validator.class.name == 'ActiveModel::Validations::ConfirmationValidator'
            names + names.map { |name| "#{name}_confirmation" }
          else
            names
          end
        end.uniq
      end

      # Validator-declared names that are not columns and that the model can
      # actually assign. Association names, column aliases and guard columns
      # are already represented (or deliberately excluded) elsewhere, so they
      # are never re-added here; a name without a public setter cannot be
      # filled and is ignored without error.
      def virtual_attribute_names(klass)
        excluded = virtual_exclusions(klass)
        validator_attribute_names(klass).reject do |name|
          excluded.include?(name) || !(settable?(klass, name) || lazily_definable?(klass, name))
        end
      end

      def settable?(klass, name)
        klass.public_method_defined?("#{name}=")
      end

      # Rails' AcceptanceValidator defines the attribute accessors lazily, the
      # first time the class is validated (its `LazilyDefineAttributes` module).
      # Before that first validation the writer does not exist, so a
      # validator-declared acceptance attribute would be missing from the
      # universe and never filled. The builder assigns through `respond_to?`,
      # which triggers the definition, so the name is safe to include.
      def lazily_definable?(klass, name)
        return false unless defined?(::ActiveModel::Validations::AcceptanceValidator)
        return false unless klass.respond_to?(:validators_on)

        klass.validators_on(name).any? do |validator|
          validator.is_a?(::ActiveModel::Validations::AcceptanceValidator)
        end
      end

      def virtual_exclusions(klass)
        names = guard_columns(klass).names + association_names(klass) + attachment_names(klass)
        names += klass.attribute_aliases.keys.map(&:to_s) if klass.respond_to?(:attribute_aliases)
        names.uniq
      end

      # Attachment libraries expose their attachments as framework
      # reflections, not columns: Active Storage's `attachment_reflections`
      # and Paperclip's `attachment_definitions`. Both declare a public
      # writer for the name, so a presence rule would otherwise pull the name
      # into the virtual universe and the core would assign a String where
      # the attachment object is expected (issue #62). The attachments plugin
      # fills these names instead; without it they are left untouched.
      def attachment_names(klass)
        names = []
        names.concat(klass.attachment_reflections.keys.map(&:to_s)) if klass.respond_to?(:attachment_reflections)
        names.concat(klass.attachment_definitions.keys.map(&:to_s)) if klass.respond_to?(:attachment_definitions)
        names
      end

      def association_names(klass)
        return [] unless klass.respond_to?(:reflect_on_all_associations)

        ReflectionCache.all(klass).map { |reflection| reflection.name.to_s }
      end

      def active_record_class?(klass)
        defined?(::ActiveRecord::Base) && klass < ::ActiveRecord::Base
      end

      def uniqueness_validators_for(klass, attr_name)
        klass.validators_on(attr_name).select do |validator|
          validator.is_a?(::ActiveRecord::Validations::UniquenessValidator)
        end
      end

      def uniqueness_validator?(klass, attr_name)
        klass.validators_on(attr_name).any? do |validator|
          validator.is_a?(::ActiveRecord::Validations::UniquenessValidator)
        end
      end

      # Columns a single-column UNIQUE index protects, memoized beside the
      # other class-level facts: the enforcer asks once per attribute per
      # record. A composite index constrains a combination, never one column,
      # so its members are not flagged (the rule the Sequel mapper applies).
      def unique_index_columns(klass)
        class_memo(klass, :@factory_bakery_unique_index_columns) do
          compute_unique_index_columns(klass).freeze
        end
      end

      def compute_unique_index_columns(klass)
        unique_indexes(klass).flat_map(&:columns).map(&:to_s).uniq
      rescue StandardError
        # A class whose table is not there (or an adapter that cannot describe
        # it) simply has no discoverable unique index.
        []
      end

      def unique_indexes(klass)
        return [] unless klass.respond_to?(:connection) && klass.respond_to?(:table_name)

        klass.connection.indexes(klass.table_name)
             .select { |index| index.unique && index.columns.length == 1 }
      end

      def build_probe(record, attr_name, value)
        probe = duplicate(record)
        probe.public_send("#{attr_name}=", value) if probe.respond_to?("#{attr_name}=")
        probe.errors.clear if probe.respond_to?(:errors)
        probe
      end

      # `dup` runs the initialize callbacks, which raise on the models the
      # construction fallback exists for (issue #56). The validator only reads
      # attributes, so such a record is probed through a callback-free copy.
      def duplicate(record)
        record.dup
      rescue StandardError => e
        raise e unless Construction.callback_free_capable?(record.class)

        Construction.copy(record)
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

      def conditional_validators?(klass, name)
        [name, name.delete_suffix('_confirmation')].uniq.any? do |candidate|
          klass.validators_on(candidate).any? { |validator| conditional_validator?(validator) }
        end
      end

      def conditional_validator?(validator)
        validator.options.key?(:if) || validator.options.key?(:unless)
      end

      def cache_for(klass)
        return nil if klass.frozen?

        klass.instance_variable_get(:@factory_bakery_constraints) ||
          klass.instance_variable_set(:@factory_bakery_constraints, {})
      end
    end
  end
end
