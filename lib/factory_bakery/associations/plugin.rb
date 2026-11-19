# frozen_string_literal: true

module FactoryBakery
  module Associations
    # The plugin object registered with core on require. It evaluates explicit
    # `association` declarations after the owner exists and delegates :all's
    # automatic collection building to AllAutoBuilder.
    #
    # Every class-level fact (kind, foreign keys, polymorphism, inverses)
    # arrives as plain association introspection from the mapper contract;
    # what remains here are orchestration decisions and operations on the
    # live record itself (its association proxies and setters).
    module Plugin
      class << self
        def dsl_module
          DSL
        end

        # belongs_to auto-build values live in the heuristics layer, so
        # declarations, traits, overrides and initialize_with keys suppress
        # them via `taken` (core expands it to whole alias groups).
        def heuristic_values(klass, context, taken)
          BelongsToBuilder.values(klass, context, taken)
        end

        # Declarations run after core has applied plain attributes, so an
        # override or trait that already decided this alias group wins and an
        # owner block sees a fully populated owner. :all collections are built
        # afterwards through the same TargetBuilder machinery.
        def after_instantiate(object, declarations, context)
          build_declared_associations(object, declarations)
          AllAutoBuilder.build(object, declarations, context)
        end

        private

        def build_declared_associations(object, declarations)
          return if declarations.empty?

          introspection = FactoryBakery::MapperRegistry.association_introspection(object.class)
          raise FactoryBakery::Error, "no associations on #{object.class}; it is not ActiveRecord" unless introspection

          winners(declarations).each_value do |declaration|
            build(object, declaration, introspection)
          end
        end

        # Base declaration first, then traits in application order. As with
        # attributes, the last declaration for a name replaces earlier ones.
        def winners(declarations)
          declarations.each_with_object({}) do |declaration, result|
            result[declaration.name] = declaration
          end
        end

        def build(object, declaration, introspection)
          entry = entry_for(object, declaration.name, introspection)
          validate!(object, declaration, entry)
          return if suppressed?(object, entry)

          if declaration.block
            assign(object, entry, declaration.block.call(object))
          else
            build_declared(object, declaration, entry)
          end
        end

        def build_declared(object, declaration, entry)
          case entry.kind
          when :has_many
            TargetBuilder.build_collection(object, declaration, entry)
          when :has_one
            assign(object, entry, TargetBuilder.bake_child(object, declaration, entry))
          else
            assign(object, entry, TargetBuilder.bake(object, declaration, entry))
          end
        end

        def assign(object, entry, target)
          object.public_send("#{entry.name}=", target)
        end

        # Checked at bake time, not definition time, so factories can load
        # before the models they name.
        def entry_for(object, name, introspection)
          entry = introspection.find { |candidate| candidate.name == name.to_s }
          raise FactoryBakery::Error, "#{object.class} has no association :#{name}" unless entry

          entry
        end

        def validate!(object, declaration, entry)
          if unsupported_shape?(entry)
            raise FactoryBakery::Error,
                  "#{object.class}##{entry.name} (#{entry.kind}) is not supported; " \
                  'assign via an attribute block'
          end
          validate_strategy!(declaration, entry)
          return if declaration.child_count.nil? || collection?(entry)

          raise ArgumentError,
                "count: is only supported on collections, but #{object.class}##{entry.name} " \
                "is a #{entry.kind} association"
        end

        # Reusing a child would rewrite its FK and steal it from another
        # owner, so only an *explicit* :reuse on a non-belongs_to edge raises.
        # An inherited scoped/global choice just skips ineligible edges.
        def validate_strategy!(declaration, entry)
          return unless ReuseResolver.strategy_for(declaration) == :reuse

          if declaration.strategy == :reuse && entry.kind != :belongs_to
            raise ArgumentError,
                  "strategy: :reuse is only supported on belongs_to, but #{qualified(entry)} " \
                  "is a #{entry.kind} association"
          end
          return unless entry.kind == :belongs_to
          return if declaration.traits.empty?

          raise ArgumentError,
                "traits cannot be combined with strategy: :reuse on #{qualified(entry)}"
        end

        def qualified(entry)
          "#{entry.target.call}##{entry.name}"
        end

        def unsupported_shape?(entry)
          entry.kind == :has_and_belongs_to_many || entry.through
        end

        def collection?(entry)
          %i[has_many has_and_belongs_to_many].include?(entry.kind)
        end

        # Core hands us the instantiated object rather than the overrides hash.
        # An explicit association assignment (including nil from a trait) marks
        # the association loaded; a foreign-key override shows up on the column.
        # Either one suppresses our declaration. For collections the FK lives on
        # the child, so only the association's loaded state can suppress it.
        def suppressed?(object, entry)
          return true if object.association(entry.name.to_sym).loaded?
          return false unless entry.kind == :belongs_to

          entry.foreign_keys.any? { |key| !object.public_send(key).nil? }
        end
      end
    end
  end
end
