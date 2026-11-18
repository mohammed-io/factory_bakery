# frozen_string_literal: true

module FactoryBakery
  module Associations
    # The plugin object registered with core on require. It evaluates explicit
    # `association` declarations; no mode auto-builds anything yet.
    module Plugin
      class << self
        def dsl_module
          DSL
        end

        # Association declarations run after core has applied plain attributes,
        # so an override or trait that already decided this alias group wins.
        def after_instantiate(object, declarations, _context)
          return if declarations.empty?

          unless object.class.respond_to?(:reflect_on_association)
            raise FactoryBakery::Error, "no associations on #{object.class}; it is not ActiveRecord"
          end

          winners(declarations).each_value { |declaration| build(object, declaration) }
        end

        private

        # Base declaration first, then traits in application order. As with
        # attributes, the last declaration for a name replaces earlier ones.
        def winners(declarations)
          declarations.each_with_object({}) do |declaration, result|
            result[declaration.name] = declaration
          end
        end

        def build(object, declaration)
          reflection = reflection_for(object, declaration.name)
          return if suppressed?(object, reflection)

          target = bake_target(object, declaration, reflection)
          object.public_send("#{reflection.name}=", target)
        end

        # A child is always built through the public bake path, so its own
        # registered factory, traits and heuristics apply. `bake` (not `bake!`)
        # keeps the graph unsaved and DB-free; bake!'s autosave transaction
        # persists the whole graph together.
        def bake_target(object, declaration, reflection)
          if reflection.polymorphic?
            require_polymorphic_factory!(object, declaration, reflection)
          elsif declaration.factory
            ensure_compatible!(object, declaration, reflection)
          end

          FactoryBakery.bake(
            declaration.factory || reflection.klass,
            *declaration.traits,
            **declaration.overrides
          )
        end

        def reflection_for(object, name)
          # Checked at bake time, not definition time, so factories can load
          # before the models they name.
          reflection = object.class.reflect_on_association(name)
          raise FactoryBakery::Error, "#{object.class} has no association :#{name}" unless reflection
          unless reflection.macro == :belongs_to
            raise FactoryBakery::Error, "association :#{name} is a #{reflection.macro}; only belongs_to is supported"
          end

          reflection
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

        # Core hands us the instantiated object rather than the overrides hash.
        # An explicit association assignment (including nil from a trait) marks
        # the association loaded; a foreign-key override shows up on the column.
        # Either one suppresses our declaration.
        def suppressed?(object, reflection)
          return true if object.association(reflection.name).loaded?

          Array(reflection.foreign_key).any? { |key| !object.public_send(key).nil? }
        end
      end
    end
  end
end
