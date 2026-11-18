# frozen_string_literal: true

module FactoryBakery
  module Associations
    # Auto-builds has_one/has_many for :all after the owner exists. It reuses
    # TargetBuilder, the same machinery explicit declarations use, so a child
    # gets its scope attributes and verified inverse before its own auto-build
    # runs. Anything already decided by a declaration or override is skipped.
    module AllAutoBuilder
      class << self
        def build(object, declarations, context)
          return unless Associations.mode == :all
          return unless object.class.respond_to?(:reflect_on_all_associations)
          return if Associations.past_depth?(context)

          declared = declarations.map { |declaration| declaration.name.to_s }
          reflections(object).each do |reflection|
            next if skip?(object, reflection, declared)

            build_child(object, reflection)
          end
        end

        private

        def reflections(object)
          ReflectionCache.all(object.class).select { |reflection| auto_buildable?(reflection) }
        end

        def auto_buildable?(reflection)
          return false unless %i[has_many has_one].include?(reflection.macro)

          !reflection.respond_to?(:through_reflection) || reflection.through_reflection.nil?
        end

        def skip?(object, reflection, declared)
          return true if declared.include?(reflection.name.to_s)
          return true if object.association(reflection.name).loaded?

          BelongsToBuilder.suppressed_edge?(object.class, reflection.name)
        end

        def build_child(object, reflection)
          declaration = Declaration.new(
            name: reflection.name,
            traits: [],
            factory: nil,
            child_count: reflection.macro == :has_many ? Associations.default_count : nil,
            overrides: {},
            block: nil
          )

          if reflection.macro == :has_many
            TargetBuilder.build_collection(object, declaration, reflection)
          else
            object.public_send("#{reflection.name}=", TargetBuilder.bake_child(object, declaration, reflection))
          end
        end
      end
    end
  end
end
