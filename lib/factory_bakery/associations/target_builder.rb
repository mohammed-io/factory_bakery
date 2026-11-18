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
    module TargetBuilder
      class << self
        # A belongs_to target has no owner-side create scope to mirror. With
        # :reuse an existing object (in this graph or in the database) wins; a
        # miss falls through to the ordinary fresh bake.
        def bake(object, declaration, reflection)
          klass = target_klass(object, declaration, reflection)
          if ReuseResolver.strategy_for(declaration) == :reuse
            existing = ReuseResolver.existing(BakeryBuilder.resolve(klass).first, declaration.overrides, reflection)
            return existing if existing
          end

          FactoryBakery.bake(klass, *declaration.traits, **declaration.overrides)
        end

        def bake_child(object, declaration, reflection)
          FactoryBakery.bake(
            target_klass(object, declaration, reflection),
            *declaration.traits,
            **child_overrides(object, reflection).merge(declaration.overrides)
          )
        end

        def build_collection(object, declaration, reflection)
          count = declaration.child_count || 1
          if count.zero?
            empty_collection(object, reflection)
            return
          end

          children = Array.new(count) { bake_child(object, declaration, reflection) }
          # concat is the public collection writer. It fires before_add/after_add
          # callbacks and sets the verified inverse on each child.
          object.public_send(reflection.name).concat(children)
        end

        private

        def child_overrides(object, reflection)
          # Rails keeps build-time attributes on the association itself; they
          # are exactly what `association.build` writes to a new record.
          scope_attributes = object.association(reflection.name).send(:scope_for_create)
          overrides = scope_attributes.transform_keys(&:to_sym)

          # Only a verified reverse reflection may bind the inverse object.
          # Without one (a scope, inverse_of: false, custom keys) the create
          # scope above still sets the FK/type and suppresses the child's
          # auto-build of this edge.
          inverse = reflection.inverse_of
          overrides[inverse.name.to_sym] = object if inverse&.belongs_to?
          overrides
        end

        def empty_collection(object, reflection)
          association = object.association(reflection.name)
          association.target = []
          association.loaded!
        end

        def target_klass(object, declaration, reflection)
          if reflection.polymorphic?
            require_polymorphic_factory!(object, declaration, reflection)
          elsif declaration.factory
            ensure_compatible!(object, declaration, reflection)
          end

          declaration.factory || reflection.klass
        end

        def require_polymorphic_factory!(object, declaration, reflection)
          return if declaration.factory

          raise FactoryBakery::Error,
                "#{object.class} has a polymorphic association :#{reflection.name}; " \
                'pass factory: to name its target class'
        end

        def ensure_compatible!(object, declaration, reflection)
          resolved, = BakeryBuilder.resolve(declaration.factory)
          expected = reflection.klass
          return if resolved <= expected

          raise FactoryBakery::Error,
                "factory: #{declaration.factory.inspect} is incompatible with #{object.class}##{declaration.name}: " \
                "expected #{expected} or a subclass, got #{resolved}"
        end
      end
    end
  end
end
