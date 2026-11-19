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
        # :reuse an existing object (in this graph or in the database) wins; a
        # miss falls through to the ordinary fresh bake.
        def bake(object, declaration, entry)
          klass = target_klass(object, declaration, entry)
          reuse = ReuseResolver.strategy_for(declaration) == :reuse
          if reuse
            resolved = BakeryBuilder.resolve(klass).first
            existing = ReuseResolver.existing(resolved, declaration.overrides, entry)
            return FkParentPersistence.persist!(existing, entry) if existing

            FkParentPersistence.raise_on_reuse_miss!(object.class, entry)
          end

          fresh = FactoryBakery.bake(klass, *declaration.traits, **declaration.overrides)
          FkParentPersistence.persist!(fresh, entry)
          ReuseResolver.remember(resolved, declaration.overrides, entry, fresh) if reuse
          fresh
        end

        def bake_child(object, declaration, entry)
          FactoryBakery.bake(
            target_klass(object, declaration, entry),
            *declaration.traits,
            **child_overrides(object, entry).merge(declaration.overrides)
          )
        end

        def build_collection(object, declaration, entry)
          count = declaration.child_count || 1
          if count.zero?
            empty_collection(object, entry)
            return
          end

          children = Array.new(count) { bake_child(object, declaration, entry) }
          # concat is the public collection writer. It fires before_add/after_add
          # callbacks and sets the verified inverse on each child.
          object.public_send(entry.name).concat(children)
        end

        private

        def child_overrides(object, entry)
          # Rails keeps build-time attributes on the association itself; they
          # are exactly what `association.build` writes to a new record.
          scope_attributes = object.association(entry.name.to_sym).send(:scope_for_create)
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

          declaration.factory || entry.target.call
        end

        def require_polymorphic_factory!(object, declaration, entry)
          return if declaration.factory

          raise FactoryBakery::Error,
                "#{object.class} has a polymorphic association :#{entry.name}; " \
                'pass factory: to name its target class'
        end

        def ensure_compatible!(object, declaration, entry)
          resolved, = BakeryBuilder.resolve(declaration.factory)
          expected = entry.target.call
          return if resolved <= expected

          raise FactoryBakery::Error,
                "factory: #{declaration.factory.inspect} is incompatible with #{object.class}##{declaration.name}: " \
                "expected #{expected} or a subclass, got #{resolved}"
        end
      end
    end
  end
end
