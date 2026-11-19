# frozen_string_literal: true

module FactoryBakery
  module Associations
    # Auto-builds a direct has_one whose presence validator applies to the
    # populated owner in :required_only. In :all, AllAutoBuilder already builds
    # every has_one, so this builder stays out of its way. The child is baked
    # through TargetBuilder, which applies the association's create scope and
    # verified inverse before the child's own heuristics run.
    module RequiredHasOneBuilder
      class << self
        def build(object, context)
          return unless Associations.mode == :required_only

          introspection = FactoryBakery::MapperRegistry.association_introspection(object.class)
          return unless introspection

          candidates(introspection, object, context).each do |entry|
            build_child(object, entry)
          end
        end

        private

        def candidates(introspection, object, context)
          taken = Array(context.taken_names)
          introspection.select { |entry| candidate?(entry, object, taken) }
        end

        def candidate?(entry, object, taken)
          return false unless entry.kind == :has_one && !entry.through
          return false if taken.include?(entry.name)
          return false if object.association(entry.name.to_sym).loaded?

          entry.presence_applicable.call(object)
        end

        def build_child(object, entry)
          declaration = Declaration.new(
            name: entry.name.to_sym,
            traits: [],
            factory: nil,
            child_count: nil,
            overrides: {},
            block: nil,
            strategy: nil
          )

          object.public_send("#{entry.name}=", TargetBuilder.bake_child(object, declaration, entry))
        end
      end
    end
  end
end
