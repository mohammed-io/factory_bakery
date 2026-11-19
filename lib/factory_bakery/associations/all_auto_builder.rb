# frozen_string_literal: true

module FactoryBakery
  module Associations
    # Auto-builds has_one/has_many for :all after the owner exists. It reuses
    # TargetBuilder, the same machinery explicit declarations use, so a child
    # gets its scope attributes and verified inverse before its own auto-build
    # runs. Anything already decided by a declaration or override is skipped.
    # The association list itself comes from the mapper's introspection.
    module AllAutoBuilder
      class << self
        def build(object, declarations, context)
          return unless Associations.mode == :all

          introspection = FactoryBakery::MapperRegistry.association_introspection(object.class)
          return unless introspection
          return if Associations.past_depth?(context)

          declared = declarations.map { |declaration| declaration.name.to_s }
          buildable_entries(introspection).each do |entry|
            next if skip?(object, entry, declared)

            build_child(object, entry)
          end
        end

        private

        def buildable_entries(introspection)
          introspection.select { |entry| auto_buildable?(entry) }
        end

        def auto_buildable?(entry)
          return false unless %i[has_many has_one].include?(entry.kind)

          !entry.through
        end

        def skip?(object, entry, declared)
          return true if declared.include?(entry.name)
          return true if object.association(entry.name.to_sym).loaded?

          BelongsToBuilder.suppressed_edge?(object.class, entry.name)
        end

        def build_child(object, entry)
          declaration = Declaration.new(
            name: entry.name.to_sym,
            traits: [],
            factory: nil,
            child_count: entry.kind == :has_many ? Associations.default_count : nil,
            overrides: {},
            block: nil
          )

          if entry.kind == :has_many
            TargetBuilder.build_collection(object, declaration, entry)
          else
            object.public_send("#{entry.name}=", TargetBuilder.bake_child(object, declaration, entry))
          end
        end
      end
    end
  end
end
