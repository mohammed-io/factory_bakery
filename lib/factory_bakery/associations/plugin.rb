# frozen_string_literal: true

module FactoryBakery
  module Associations
    # The plugin object registered with core on require. It only evaluates
    # explicit `association` declarations; no mode auto-builds anything yet.
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

          declarations.uniq.each { |name| build(object, name) }
        end

        private

        def build(object, name)
          # Checked at bake time, not definition time, so factories can load
          # before the models they name.
          reflection = object.class.reflect_on_association(name)
          raise FactoryBakery::Error, "#{object.class} has no association :#{name}" unless reflection
          unless reflection.macro == :belongs_to
            raise FactoryBakery::Error, "association :#{name} is a #{reflection.macro}; only belongs_to is supported"
          end

          return if suppressed?(object, reflection)

          # bake (not bake!) keeps the graph unsaved and DB-free, and the target
          # class's own factory and heuristics apply because we bake the class.
          # Assigning through the reflection sets the FK; core already excludes
          # belongs_to FK columns from its heuristic layer, so nothing can
          # clobber the value afterwards.
          object.public_send("#{reflection.name}=", FactoryBakery.bake(reflection.klass))
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
