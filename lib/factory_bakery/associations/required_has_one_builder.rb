# frozen_string_literal: true

module FactoryBakery
  module Associations
    # Auto-builds a direct has_one whose presence validator applies to the
    # populated owner in :required_only. In :all, AllAutoBuilder already builds
    # every has_one within max_depth, so this builder only takes over past it:
    # a record there gets no optional children, but a required has_one is
    # still part of a valid record (Discourse's User#primary_email), and Rails'
    # belongs_to autosave silently skips an invalid parent, inserting the child
    # with a nil foreign key. The child is baked through TargetBuilder, which
    # applies the association's create scope and verified inverse before the
    # child's own heuristics run.
    module RequiredHasOneBuilder
      class << self
        def build(object, context)
          return unless Associations.mode == :required_only || Associations.past_depth?(context)

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
          return false unless foreign_keys_exist?(entry)

          entry.presence_applicable.call(object)
        end

        # A has_one whose foreign key the target cannot store is dead
        # (Discourse's `Topic has_many :user_profiles`): building it would
        # write an unknown attribute. The column facts come from the mapper.
        def foreign_keys_exist?(entry)
          target = entry.resolve_target

          entry.foreign_keys.all? { |key| FactoryBakery::MapperRegistry.column?(target, key) }
        rescue StandardError
          false
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

          object.public_send("#{entry.name}=", TargetBuilder.bake_child(object, declaration, entry, automatic: true))
        end
      end
    end
  end
end
