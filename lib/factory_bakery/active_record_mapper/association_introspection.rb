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
    #
    # The result is memoized on the class (a bake asks several times);
    # reloading a class drops the cache with it. A frozen class is read
    # without caching, matching the constraints cache's own handling.
    module AssociationIntrospection
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

        ReflectionCache.all(klass).map { |reflection| entry(klass, reflection, detector) }.freeze
      end

      def entry(klass, reflection, detector)
        FactoryBakery::MapperRegistry::Association.new(
          name: reflection.name.to_s,
          kind: reflection.macro,
          target_class_name: reflection.class_name,
          foreign_keys: foreign_keys(reflection),
          foreign_type: foreign_type(reflection),
          polymorphic: reflection.polymorphic?,
          counter_cache_columns: counter_columns(reflection, detector),
          required: required?(klass, reflection),
          scope: association_scope(reflection),
          through: through_association?(reflection),
          **lazy_resolvers(reflection)
        ).freeze
      end

      # `foreign_key` is an array for composite FKs and a string otherwise.
      def foreign_keys(reflection)
        Array(reflection.foreign_key).map(&:to_s).freeze
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
      # is required at the database level. `reflection.options[:optional]` is
      # deliberately never read -- plain ActiveRecord defaults it to optional.
      # Only a belongs_to edge can be required.
      def required?(klass, reflection)
        return false unless reflection.macro == :belongs_to

        presence_validator?(klass, reflection) || not_null_foreign_key?(klass, reflection)
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
      # the inverse's name and its kind.
      def lazy_resolvers(reflection)
        {
          target: -> { reflection.klass },
          inverse_name: -> { reflection.inverse_of&.name },
          inverse_kind: -> { reflection.inverse_of&.macro }
        }
      end
    end
  end
end
