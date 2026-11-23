# frozen_string_literal: true

module FactoryBakery
  module ActiveRecordMapper
    # Builds the plain per-association data the associations orchestration
    # consumes. Every read mirrors what the plugin used to read off the
    # reflection directly, so the emitted values -- including the moment an
    # error would have been raised -- are byte-identical.
    #
    # Fragile derivations (an unloadable target class, an underivable
    # inverse) stay lazy inside the returned callables: they run exactly when
    # the edge is used, never while merely listing a class's associations.
    # A reflection that fails even to be described is dropped from the list
    # and recorded on the result, so one half-loaded association cannot
    # poison every other edge on the class.
    #
    # The result is memoized on the class (a bake asks several times);
    # reloading a class drops the cache with it. A frozen class is read
    # without caching, matching the constraints cache's own handling.
    module AssociationIntrospection # rubocop:disable Metrics/ModuleLength
      module_function

      # nil marks a class that is not association-introspectable at all,
      # which callers distinguish from an introspectable class with no
      # associations (an empty array).
      def for(klass)
        return nil unless klass.respond_to?(:reflect_on_all_associations)

        return build(klass) if klass.frozen?

        klass.instance_variable_get(:@factory_bakery_associations) ||
          klass.instance_variable_set(:@factory_bakery_associations, build(klass))
      end

      def build(klass)
        detector = CounterCacheDetector.new(klass)
        failures = {}

        entries = ReflectionCache.all(klass).filter_map do |reflection|
          entry(klass, reflection, detector)
        rescue StandardError => e
          failures[reflection_name(reflection)] = "#{e.class}: #{e.message}"
          nil
        end

        FactoryBakery::MapperRegistry::Introspection.new(entries, failures)
      rescue StandardError => e
        # A class whose whole reflection set cannot be read is still
        # introspectable; it simply has no usable associations. Keep the
        # [] contract distinct from the nil "no mapper can see this class".
        FactoryBakery::MapperRegistry::Introspection.new([], { nil => "#{e.class}: #{e.message}" })
      end

      def reflection_name(reflection)
        reflection.name.to_s
      rescue StandardError
        '<unknown>'
      end

      def entry(klass, reflection, detector)
        FactoryBakery::MapperRegistry::Association.new(
          name: reflection.name.to_s,
          kind: reflection.macro,
          target_class_name: reflection.class_name,
          foreign_keys: foreign_keys(klass, reflection),
          foreign_type: foreign_type(reflection),
          polymorphic: reflection.polymorphic?,
          counter_cache_columns: counter_columns(reflection, detector),
          natural_key_name: NaturalKey.key_name(reflection),
          required: required?(klass, reflection),
          fk_presence: fk_presence?(klass, reflection),
          scope: association_scope(reflection),
          through: through_association?(reflection),
          **lazy_resolvers(klass, reflection)
        ).freeze
      end

      # `foreign_key` is an array for composite FKs and a string otherwise.
      #
      # A HABTM join model's `belongs_to :left_side` is synthetic: Rails
      # declares it without a real foreign key, so the reflection answers
      # `left_side_id` even though the join table only has the owner's real
      # column (`post_id`). Report that real column instead, so the
      # association builder assigns the column that exists.
      def foreign_keys(klass, reflection)
        keys = Array(reflection.foreign_key).map(&:to_s)
        join_key = habtm_join_left_key(klass, reflection)
        return [join_key].freeze if join_key

        keys.freeze
      end

      def habtm_join_left_key(klass, reflection)
        return nil unless reflection.macro == :belongs_to
        return nil unless reflection.name.to_s == 'left_side'
        return nil unless klass.respond_to?(:columns_hash)

        owner = reflection.options[:anonymous_class]
        return nil unless owner.is_a?(Class) && owner.name

        key = owner.name.foreign_key
        key if klass.columns_hash.key?(key)
      end

      def foreign_type(reflection)
        reflection.foreign_type.to_s if reflection.polymorphic?
      end

      def through_association?(reflection)
        reflection.respond_to?(:through_reflection) && !reflection.through_reflection.nil?
      end

      def counter_columns(reflection, detector)
        return [].freeze unless %i[has_many has_one].include?(reflection.macro)

        detector.column_names_for(reflection).compact.uniq.freeze
      end

      # Heuristic-first detection: Rails materializes "required" as a
      # PresenceValidator on the association name regardless of which setting
      # produced it (including on: :create and if:/unless:), and a NOT NULL FK
      # is required at the database level. A presence validator on the raw FK
      # column is required too, but is reported separately by `fk_presence?` so
      # callers can persist the parent (the only way to give the column a real
      # value). `reflection.options[:optional]` is deliberately never read for
      # id-keyed edges -- plain ActiveRecord defaults them to optional, so the
      # NOT NULL FK is their only required signal. Natural keys (issue #54) are
      # different: the FK is a real data column the child fills itself, so a
      # NOT NULL column there must not force a parent when the association is
      # optional; only an explicit validator counts. Only belongs_to can be
      # required.
      def required?(klass, reflection)
        return false unless reflection.macro == :belongs_to

        if NaturalKey.natural?(reflection)
          return fk_presence?(klass, reflection) || presence_validator?(klass, reflection)
        end

        fk_presence?(klass, reflection) ||
          presence_validator?(klass, reflection) ||
          not_null_foreign_key?(klass, reflection)
      end

      # True when the required signal is the FK COLUMN rather than the
      # association. Unsaved parents have a nil id, so such a column can only
      # pass presence validation once the parent has been persisted.
      # Polymorphic edges keep their existing behavior (no auto-build from a
      # raw FK signal), so they are deliberately excluded here.
      def fk_presence?(klass, reflection)
        return false unless reflection.macro == :belongs_to
        return false if reflection.polymorphic?
        return false unless klass.respond_to?(:validators_on)

        Array(reflection.foreign_key).any? do |key|
          klass.validators_on(key).any? { |validator| validator.is_a?(ActiveModel::Validations::PresenceValidator) }
        end
      end

      def presence_validator?(klass, reflection)
        return false unless klass.respond_to?(:validators_on)

        klass.validators_on(reflection.name).any? do |validator|
          validator.is_a?(ActiveModel::Validations::PresenceValidator)
        end
      end

      def not_null_foreign_key?(klass, reflection)
        return false unless klass.respond_to?(:columns_hash)

        Array(reflection.foreign_key).any? do |key|
          column = klass.columns_hash[key.to_s]
          column && !column.null
        end
      end

      # The scope lambda as raw data; it stays the very same object the
      # reflection holds, so the reuse cache can keep keying on it.
      def association_scope(reflection)
        return nil unless reflection.respond_to?(:scope)

        reflection.scope
      rescue StandardError
        # Exotic edges (a through association's delegated scope) must never
        # break listing a class's associations; the value is only consumed
        # when the edge is actually followed.
        nil
      end

      # The callables carrying the fragile derivations: target resolution,
      # the inverse's name and kind, and record-specific presence requirements.
      def lazy_resolvers(klass, reflection)
        inverse = -> { AssociationRequirements.inverse(reflection) }
        {
          target: -> { resolve_target(klass, reflection) },
          inverse_name: -> { inverse.call&.name },
          inverse_kind: -> { inverse.call&.macro },
          presence_applicable: ->(record) { AssociationRequirements.presence_applicable?(klass, reflection, record) },
          class_missing: -> { class_missing?(reflection) }
        }
      end

      # Rails resolves the declared class for its own writer and reader. Without
      # a constant those raise, so the foreign key is the only way to point the
      # record at a parent. Polymorphic edges have no single class to ask.
      def class_missing?(reflection)
        return false unless reflection.macro == :belongs_to && !reflection.polymorphic?

        reflection.klass
        false
      rescue NameError
        true
      end

      # `reflection.klass` is the ordinary resolution. An application may map a
      # stored class name to a class of its own (Discourse maps "ChatMessage" to
      # Chat::Message), so the owner is asked next. A class name with no constant
      # at all can still resolve through the database: the owner's foreign key
      # constraint names the table the row points at. Only then does the original
      # NameError surface.
      def resolve_target(klass, reflection)
        reflection.klass
      rescue NameError => e
        mapped_target(klass, reflection) || foreign_key_target(klass, reflection) || raise(e)
      end

      def mapped_target(klass, reflection)
        return nil unless klass.respond_to?(:polymorphic_class_for)

        candidate = klass.polymorphic_class_for(reflection.class_name)
        candidate.is_a?(Class) ? candidate : nil
      rescue StandardError
        nil
      end

      def foreign_key_target(klass, reflection)
        table = ForeignKeyTargets.referenced_table(klass, reflection.foreign_key)
        table && ForeignKeyTargets.model_for_table(table)
      end
    end
  end
end
