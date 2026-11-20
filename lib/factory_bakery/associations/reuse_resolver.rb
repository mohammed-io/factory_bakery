# frozen_string_literal: true

require 'date'

module FactoryBakery
  module Associations
    # Finds an existing target for a `strategy: :reuse_non_unique` edge. A
    # strict per-bake cache is checked first, then the database. A miss returns
    # nil and the caller builds fresh (unsaved under `bake`).
    #
    # The association facts arrive as plain introspection data (`scope` is the
    # very Proc the mapper copied off the reflection, so cache keys stay
    # identical); the class-level reads below (primary key, columns, attribute
    # types, the lookup query) are duck-typed calls on the target class, never
    # framework constants.
    #
    # The cache key is the resolved target class (exact STI class), the
    # association scope, and the normalized scalar overrides. Factory symbols,
    # traits and non-scalar overrides are never part of it. Objects are only
    # entered once their build is complete, and an ancestor is never handed out
    # because that would close a cycle.
    module ReuseResolver # rubocop:disable Metrics/ModuleLength
      SCALAR_CLASSES = [String, Numeric, Symbol, Date, Time, TrueClass, FalseClass, NilClass].freeze

      class << self # rubocop:disable Metrics/ClassLength
        # Most specific setting wins: the association, then the scope, then the
        # global value. :fresh is the default.
        def strategy_for(declaration)
          declaration&.strategy || Associations.strategy
        end

        # `:reuse_non_unique` takes an existing target only when the edge
        # cannot be unique: a foreign key with any uniqueness (a uniqueness
        # validator, a single or composite unique index) or a `has_one`
        # inverse means one row per owner, so a fresh target is built instead,
        # exactly as `:fresh` does. Such an edge is never looked up and never
        # remembered.
        def reuse?(owner_class, declaration, entry)
          return false unless strategy_for(declaration) == :reuse_non_unique
          return false unless entry.kind == :belongs_to

          !unique?(owner_class, entry)
        end

        # `overrides` are the values passed to this association. Only scalar,
        # column-backed values can be matched; anything else falls back to a
        # fresh build. Encrypted and serialized attributes cannot be matched at
        # all and fail loudly.
        def existing(klass, overrides, entry)
          return nil unless klass.respond_to?(:columns_hash)

          key = match_key(klass, overrides, entry)
          return nil unless key

          cached = cached_object(key)
          return cached if cached

          database_match(klass, key.last, entry).tap do |object|
            # A database hit becomes the in-graph source of truth too, so two
            # paths in one bake share the very same object. A persisted row is
            # already complete, so it has no in-progress build path to guard.
            remember_object(key, object, nil) if object
          end
        end

        # Registers an object that the caller just built after a miss. Only
        # :reuse_non_unique edges call this, so a :fresh build never writes the
        # cache.
        def remember(klass, overrides, entry, object)
          return unless object && klass.respond_to?(:columns_hash)

          key = match_key(klass, overrides, entry)
          remember_object(key, object, build_path_for(object)) if key
        end

        # Public so callers can resolve and remember against the exact same key
        # they looked up. Returns nil when the overrides are not matchable.
        def match_key(klass, overrides, entry)
          return nil unless klass.respond_to?(:columns_hash)

          validate_pk!(klass)
          validate_matchable!(klass, overrides)
          match = matchable_overrides(klass, overrides)
          return nil unless match

          [klass, scope_signature(entry), match]
        end

        private

        # Any uniqueness on the edge makes a reused row wrong: the owner would
        # have two rows competing for one target (or one target for two
        # owners). The mapper reports both validator-backed uniqueness and
        # single-column unique indexes; `unique_index_groups` adds the
        # composite indexes the per-attribute check deliberately ignores.
        def unique?(owner_class, entry)
          columns = Array(entry.foreign_keys).map(&:to_s)

          unique_index?(owner_class, columns) ||
            columns.any? { |column| FactoryBakery::MapperRegistry.uniqueness_validated?(owner_class, column) } ||
            FactoryBakery::MapperRegistry.uniqueness_validated?(owner_class, entry.name.to_s) ||
            has_one_inverse?(entry)
        end

        # Inverse detection loads the target class, which a broken or missing
        # constant can make raise; an unknown inverse is not a has_one.
        def has_one_inverse?(entry) # rubocop:disable Naming/PredicatePrefix
          entry.inverse_kind.call == :has_one
        rescue StandardError
          false
        end

        def unique_index?(owner_class, columns)
          wanted = columns.map(&:to_s)

          FactoryBakery::MapperRegistry.unique_index_groups(owner_class).any? do |group|
            group.any? { |column| wanted.include?(column) }
          end
        end

        def validate_pk!(klass)
          primary_key = klass.primary_key
          return if primary_key.is_a?(String) || primary_key.is_a?(Symbol)

          raise ArgumentError,
                'strategy: :reuse_non_unique needs a single primary key to pick deterministically, ' \
                "but #{klass} has #{primary_key.inspect}"
        end

        def validate_matchable!(klass, overrides)
          return unless klass.respond_to?(:attribute_types)

          overrides.each_key do |name|
            key = name.to_s
            if encrypted?(klass, key)
              raise ArgumentError,
                    "strategy: :reuse_non_unique cannot match encrypted attribute #{key.inspect} on #{klass}"
            end
            if serialized?(klass, key)
              raise ArgumentError,
                    "strategy: :reuse_non_unique cannot match serialized column #{key.inspect} on #{klass}"
            end
          end
        end

        def encrypted?(klass, key)
          if klass.respond_to?(:encrypted_attributes) && klass.encrypted_attributes &&
             (klass.encrypted_attributes.include?(key.to_sym) || klass.encrypted_attributes.include?(key))
            return true
          end

          klass.attribute_types[key]&.class&.name == 'ActiveRecord::Encryption::EncryptedAttributeType'
        end

        def serialized?(klass, key)
          type = klass.attribute_types[key]
          return false unless type

          # An ancestors-name check is exactly what the framework's own
          # `is_a?` answers, without naming its constant here; the suffix
          # check keeps covering aliased subclasses as before.
          type.class.ancestors.any? { |ancestor| ancestor.name == 'ActiveRecord::Type::Serialized' } ||
            type.class.name.end_with?('Type::Serialized')
        end

        def matchable_overrides(klass, overrides)
          overrides.each_with_object({}) do |(name, value), match|
            key = name.to_s
            return nil unless klass.columns_hash.key?(key) && scalar?(value)

            match[key] = value
          end
        end

        def scalar?(value)
          SCALAR_CLASSES.any? { |type| value.is_a?(type) }
        end

        # Two associations with the same class but different scopes must not
        # share an instance. A scope that needs arguments is never applied to
        # the lookup, so it does not distinguish entries either. The entry's
        # scope is the very Proc the reflection held, so cache keys written
        # before the rework still match.
        def scope_signature(entry)
          scope = entry&.scope
          return nil unless scope
          return nil if scope.arity.positive?

          scope
        end

        def cached_object(key)
          entry = BuildContext.graph_object(key)
          return unless entry

          path, object = entry
          return object if path.nil?

          # A completed sibling is shareable; an ancestor still on the stack is
          # not, because reusing one would close a cycle.
          return if ancestor?(path, BuildContext.current.path)

          object
        end

        def remember_object(key, object, path)
          BuildContext.record_graph_object(key, path, object)
        end

        # The path recorded by core when the freshly built object completed.
        def build_path_for(object)
          BuildContext.generated_records.reverse_each.find { |entry| entry.object.equal?(object) }&.path
        end

        def ancestor?(record_path, current_path)
          record_path.length < current_path.length &&
            current_path[0, record_path.length] == record_path
        end

        def database_match(klass, overrides, entry)
          scope = klass.all
          scope = apply_association_scope(scope, entry)
          scope = apply_sti(scope, klass)
          scope = scope.where(overrides) unless overrides.empty?
          # `reorder` (not `order`) so a default scope cannot change the pick.
          scope.reorder(klass.primary_key).first
        end

        def apply_association_scope(scope, entry)
          association_scope = entry&.scope
          return scope unless association_scope
          return scope unless association_scope.arity <= 0

          scope.instance_exec(&association_scope)
        end

        # An STI base query otherwise includes every subclass row, and a
        # subclass query includes its descendants. Restrict to exactly the
        # resolved factory class in both cases.
        def apply_sti(scope, klass)
          return scope unless klass.respond_to?(:inheritance_column)

          column = klass.inheritance_column
          return scope if column.nil? || column.to_s.empty?
          return scope unless klass.columns_hash.key?(column.to_s)

          scope.where(column => klass.sti_name)
        end
      end
    end
  end
end
