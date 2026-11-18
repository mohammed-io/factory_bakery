# frozen_string_literal: true

module FactoryBakery
  module Associations
    # The plugin object registered with core on require. It evaluates explicit
    # `association` declarations after the owner exists and, in :required_only
    # mode, auto-builds required belongs_to through core's heuristic values hook.
    module Plugin
      class << self
        def dsl_module
          DSL
        end

        # Auto-build values live in the heuristics layer, so declarations,
        # traits, overrides and initialize_with keys suppress them via `taken`.
        def heuristic_values(klass, context, taken)
          RequiredBuilder.values(klass, context, taken)
        end

        # Association declarations run after core has applied plain attributes,
        # so an override or trait that already decided this alias group wins and
        # an owner block sees a fully populated owner.
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
          validate!(object, declaration, reflection)
          return if suppressed?(object, reflection)

          if declaration.block
            assign(object, reflection, declaration.block.call(object))
          else
            build_declared(object, declaration, reflection)
          end
        end

        def build_declared(object, declaration, reflection)
          case reflection.macro
          when :has_many
            TargetBuilder.build_collection(object, declaration, reflection)
          when :has_one
            assign(object, reflection, TargetBuilder.bake_child(object, declaration, reflection))
          else
            assign(object, reflection, TargetBuilder.bake(object, declaration, reflection))
          end
        end

        def assign(object, reflection, target)
          object.public_send("#{reflection.name}=", target)
        end

        def reflection_for(object, name)
          # Checked at bake time, not definition time, so factories can load
          # before the models they name.
          reflection = object.class.reflect_on_association(name)
          raise FactoryBakery::Error, "#{object.class} has no association :#{name}" unless reflection

          reflection
        end

        def validate!(object, declaration, reflection)
          if unsupported_shape?(reflection)
            raise FactoryBakery::Error,
                  "#{object.class}##{reflection.name} (#{reflection.macro}) is not supported; " \
                  'assign via an attribute block'
          end
          return if declaration.child_count.nil? || reflection.collection?

          raise ArgumentError,
                "count: is only supported on collections, but #{object.class}##{reflection.name} " \
                "is a #{reflection.macro} association"
        end

        def unsupported_shape?(reflection)
          return true if reflection.macro == :has_and_belongs_to_many

          reflection.respond_to?(:through_reflection) && !reflection.through_reflection.nil?
        end

        # Core hands us the instantiated object rather than the overrides hash.
        # An explicit association assignment (including nil from a trait) marks
        # the association loaded; a foreign-key override shows up on the column.
        # Either one suppresses our declaration. For collections the FK lives on
        # the child, so only the association's loaded state can suppress it.
        def suppressed?(object, reflection)
          return true if object.association(reflection.name).loaded?
          return false unless reflection.macro == :belongs_to

          Array(reflection.foreign_key).any? { |key| !object.public_send(key).nil? }
        end
      end
    end
  end
end
