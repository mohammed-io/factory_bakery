# frozen_string_literal: true

require 'date'

module FactoryBakery
  module Associations
    # Finds an existing target for a `strategy: :reuse` edge. The in-graph
    # registry from core's build context is checked first, then the database.
    # A miss returns nil and the caller builds fresh (unsaved under `bake`).
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

          validate_pk!(klass)
          validate_matchable!(klass, overrides)
          match = matchable_overrides(klass, overrides)
          return nil unless match

          in_graph = in_graph_match(klass, match)
          return in_graph if in_graph

          database_match(klass, match, reflection).tap do |object|
            # A database hit becomes the in-graph source of truth too, so two
            # paths in one bake share the very same object.
            BuildContext.record_generated(object) if object
          end
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

        # A record's path is its class path at bake time. Records generated at
        # an ancestor path are the current bake's own ancestors and are never
        # shared, since reusing one would create a cycle.
        def in_graph_match(klass, overrides)
          context = BuildContext.current
          current_path = context.path
          context.generated_records.reverse_each.find do |record_path, object|
            next false if ancestor?(record_path, current_path)
            next false unless object.instance_of?(klass)

            matches_in_memory?(klass, object, overrides)
          end&.last
        end

        def ancestor?(record_path, current_path)
          record_path.length < current_path.length &&
            current_path[0, record_path.length] == record_path
        end

        def matches_in_memory?(klass, object, overrides)
          overrides.all? do |name, value|
            next false unless object.respond_to?(name)

            object.public_send(name) == klass.type_for_attribute(name).cast(value)
          end
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
