# frozen_string_literal: true

require 'date'

module FactoryBakery
  module Associations
    # Finds an existing target for a `strategy: :reuse` edge. A strict per-bake
    # cache is checked first, then the database. A miss returns nil and the
    # caller builds fresh (unsaved under `bake`).
    #
    # The cache key is the resolved target class (exact STI class), the
    # association scope, and the normalized scalar overrides. Factory symbols,
    # traits and non-scalar overrides are never part of it. Objects are only
    # entered once their build is complete, and an ancestor is never handed out
    # because that would close a cycle.
    module ReuseResolver
      SCALAR_CLASSES = [String, Numeric, Symbol, Date, Time, TrueClass, FalseClass, NilClass].freeze

      class << self
        # Most specific setting wins: the association, then the scope, then the
        # global value. :fresh is the default.
        def strategy_for(declaration)
          declaration&.strategy || Associations.strategy
        end

        # `overrides` are the values passed to this association. Only scalar,
        # column-backed values can be matched; anything else falls back to a
        # fresh build. Encrypted and serialized attributes cannot be matched at
        # all and fail loudly.
        def existing(klass, overrides, reflection)
          return nil unless klass.respond_to?(:columns_hash)

          key = match_key(klass, overrides, reflection)
          return nil unless key

          cached = cached_object(key)
          return cached if cached

          database_match(klass, key.last, reflection).tap do |object|
            # A database hit becomes the in-graph source of truth too, so two
            # paths in one bake share the very same object. A persisted row is
            # already complete, so it has no in-progress build path to guard.
            remember_object(key, object, nil) if object
          end
        end

        # Registers an object that the caller just built after a miss. Only
        # :reuse edges call this, so a :fresh build never writes the cache.
        def remember(klass, overrides, reflection, object)
          return unless object && klass.respond_to?(:columns_hash)

          key = match_key(klass, overrides, reflection)
          remember_object(key, object, build_path_for(object)) if key
        end

        # Public so callers can resolve and remember against the exact same key
        # they looked up. Returns nil when the overrides are not matchable.
        def match_key(klass, overrides, reflection)
          return nil unless klass.respond_to?(:columns_hash)

          validate_pk!(klass)
          validate_matchable!(klass, overrides)
          match = matchable_overrides(klass, overrides)
          return nil unless match

          [klass, scope_signature(reflection), match]
        end

        private

        def validate_pk!(klass)
          primary_key = klass.primary_key
          return if primary_key.is_a?(String) || primary_key.is_a?(Symbol)

          raise ArgumentError,
                'strategy: :reuse needs a single primary key to pick deterministically, ' \
                "but #{klass} has #{primary_key.inspect}"
        end

        def validate_matchable!(klass, overrides)
          return unless klass.respond_to?(:attribute_types)

          overrides.each_key do |name|
            key = name.to_s
            if encrypted?(klass, key)
              raise ArgumentError, "strategy: :reuse cannot match encrypted attribute #{key.inspect} on #{klass}"
            end
            if serialized?(klass, key)
              raise ArgumentError, "strategy: :reuse cannot match serialized column #{key.inspect} on #{klass}"
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

          (defined?(ActiveRecord::Type::Serialized) && type.is_a?(ActiveRecord::Type::Serialized)) ||
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
        # the lookup, so it does not distinguish entries either.
        def scope_signature(reflection)
          scope = reflection&.scope
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
          BuildContext.generated_records.reverse_each.find { |_, recorded| recorded.equal?(object) }&.first
        end

        def ancestor?(record_path, current_path)
          record_path.length < current_path.length &&
            current_path[0, record_path.length] == record_path
        end

        def database_match(klass, overrides, reflection)
          scope = klass.all
          scope = apply_association_scope(scope, reflection)
          scope = apply_sti(scope, klass)
          scope = scope.where(overrides) unless overrides.empty?
          # `reorder` (not `order`) so a default scope cannot change the pick.
          scope.reorder(klass.primary_key).first
        end

        def apply_association_scope(scope, reflection)
          association_scope = reflection&.scope
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
