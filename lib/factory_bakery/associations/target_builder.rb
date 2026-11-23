# frozen_string_literal: true

module FactoryBakery
  module Associations
    # Builds association targets through the owner's association semantics.
    #
    # A child gets the association's own create scope (FK, polymorphic type and
    # scope attributes) plus its verified inverse as overrides to its public
    # bake, before the child's heuristics and auto-build run. Adding the child
    # through the collection writer then lets Rails fire callbacks and wire the
    # inverse exactly as `association.build` would.
    #
    # What the edge is (kind, target, inverse) arrives as plain association
    # introspection from the mapper contract; the record-level operations
    # below (the association proxy, the collection writer) run on the live
    # owner exactly as before.
    module TargetBuilder
      class << self
        # A belongs_to target has no owner-side create scope to mirror. With
        # :reuse_non_unique an existing object (in this graph or in the
        # database) wins when the edge cannot be unique; a miss, or any unique
        # edge, falls through to the ordinary fresh bake, exactly as :fresh
        # does.
        def bake(object, declaration, entry)
          klass = target_klass(object, declaration, entry)
          reuse = ReuseResolver.reuse?(object.class, declaration, entry)
          if reuse
            resolved = BakeryBuilder.resolve(klass).first
            existing = ReuseResolver.existing(resolved, declaration.overrides, entry)
            return FkParentPersistence.settle(existing, object, entry) if existing
          end

          fresh = bake_fresh(object, declaration, entry, klass)
          ReuseResolver.remember(resolved, declaration.overrides, entry, fresh) if reuse
          fresh
        end

        # `persist: true` is a nested `bake!`: the target and its whole graph
        # are saved (and verified) before the owner is validated, inside the
        # caller's transaction when there is one. Otherwise the edge decides.
        def bake_fresh(object, declaration, entry, klass)
          return FactoryBakery.bake!(klass, *declaration.traits, **declaration.overrides) if declaration.persist

          FkParentPersistence.build(object, entry) do
            FactoryBakery.bake(klass, *declaration.traits, **declaration.overrides)
          end
        end

        # `shared_scope` lets a collection pass the owner's create scope once
        # for all its children, but only when the child class has no default
        # scopes: `scope_for_create` reads the target's default_scope too, and
        # a scope whose value changes per evaluation (a counter, a clock) must
        # not be frozen onto every child. When it is nil, each child asks for
        # its own.
        def bake_child(object, declaration, entry, automatic: false, shared_scope: nil)
          klass = target_klass(object, declaration, entry)
          overrides = child_overrides(object, entry, shared_scope).merge(declaration.overrides)
          return FactoryBakery.bake(klass, *declaration.traits, **overrides) unless automatic

          BuildContext.automatic_build { FactoryBakery.bake(klass, *declaration.traits, **overrides) }
        end

        def build_collection(object, declaration, entry, automatic: false)
          count = declaration.child_count || 1
          if count.zero?
            empty_collection(object, entry)
            return
          end

          klass = target_klass(object, declaration, entry)
          if klass.respond_to?(:default_scopes) && klass.default_scopes.empty?
            shared_scope = create_scope(object, entry)
          end
          children = Array.new(count) do
            bake_child(object, declaration, entry, automatic: automatic, shared_scope: shared_scope)
          end
          # concat is the public collection writer. It fires before_add/after_add
          # callbacks and sets the verified inverse on each child.
          object.public_send(entry.name).concat(children)
        end

        private

        # Rails keeps build-time attributes on the association itself; they
        # are exactly what `association.build` writes to a new record.
        def create_scope(object, entry)
          object.association(entry.name.to_sym).send(:scope_for_create)
        end

        def child_overrides(object, entry, shared_scope = nil)
          scope_attributes = shared_scope || create_scope(object, entry)
          overrides = scope_attributes.transform_keys(&:to_sym)

          # Only a verified reverse reflection may bind the inverse object.
          # Without one (a scope, inverse_of: false, custom keys) the create
          # scope above still sets the FK/type and suppresses the child's
          # auto-build of this edge.
          inverse_name = entry.inverse_name.call
          inverse_kind = entry.inverse_kind.call
          overrides[inverse_name.to_sym] = object if !inverse_name.nil? && inverse_kind == :belongs_to
          overrides
        end

        def empty_collection(object, entry)
          association = object.association(entry.name.to_sym)
          association.target = []
          association.loaded!
        end

        def target_klass(object, declaration, entry)
          if entry.polymorphic
            require_polymorphic_factory!(object, declaration, entry)
          elsif declaration.factory
            ensure_compatible!(object, declaration, entry)
          end

          declaration.factory || entry.resolve_target
        end

        def require_polymorphic_factory!(object, declaration, entry)
          return if declaration.factory

          raise FactoryBakery::Error,
                "#{object.class} has a polymorphic association :#{entry.name}; " \
                'pass factory: to name its target class'
        end

        def ensure_compatible!(object, declaration, entry)
          resolved, = BakeryBuilder.resolve(declaration.factory)
          expected = entry.resolve_target
          return if resolved <= expected

          raise FactoryBakery::Error,
                "factory: #{declaration.factory.inspect} is incompatible with #{object.class}##{declaration.name}: " \
                "expected #{expected} or a subclass, got #{resolved}"
        end
      end
    end
  end
end
