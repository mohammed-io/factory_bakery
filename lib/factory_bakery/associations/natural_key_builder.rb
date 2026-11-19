# frozen_string_literal: true

module FactoryBakery
  module Associations
    # Natural-key belongs_to edges (`foreign_key: :domain, primary_key: :domain`)
    # differ from id-keyed ones: their FK is ordinary data the child fills
    # itself, and a parent that is built must carry that exact same key
    # (issue #54). The build therefore runs after instantiation, when the FK
    # value -- a call-site override, a declaration or a heuristic fill -- is
    # already on the object. The value is passed to the parent as an override,
    # and assigning the parent writes the same value straight back to the FK.
    #
    # The edge's shape arrives as plain association introspection from the
    # mapper; only the final bake and the association writer run on the live
    # object, as in the other auto-builders.
    module NaturalKeyBuilder
      class << self
        def build(object, context)
          return if Associations.mode == :none

          introspection = FactoryBakery::MapperRegistry.association_introspection(object.class)
          return unless introspection

          explicit = Array(context.explicit_names)
          candidates(introspection, object, context, explicit).each do |entry|
            build_parent(object, entry, explicit)
          end
        end

        private

        def candidates(introspection, object, context, explicit)
          introspection.select do |entry|
            buildable?(entry, context) &&
              !explicit.include?(entry.name) &&
              !object.association(entry.name.to_sym).loaded?
          end
        end

        # Required edges are always built; optional ones are an :all-only
        # feature and stop at the same depth budget as the other auto-builder.
        def buildable?(entry, context)
          return false unless entry.kind == :belongs_to && entry.natural_key_name && entry.foreign_keys.one?

          entry.required || (Associations.mode == :all && !Associations.past_depth?(context))
        end

        # The child's FK is a call-site override, a declaration or a heuristic
        # fill. When a required edge still has no value -- a nullable FK column
        # under :required_only -- the parent is baked first and its generated
        # key copied into the child, so the pair always agrees and the record
        # validates. An explicitly skipped FK is left alone.
        def build_parent(object, entry, explicit)
          key = entry.foreign_keys.first
          value = object.public_send(key) if object.respond_to?(key)
          return build_from_value(object, entry, value) unless missing?(value)
          return unless entry.required
          return if explicit.include?(key)

          build_from_generated_key(object, entry, key)
        end

        def build_from_value(object, entry, value)
          parent = FactoryBakery.bake(entry.resolve_target, entry.natural_key_name => value)
          object.public_send("#{entry.name}=", parent)
        end

        def build_from_generated_key(object, entry, key)
          parent = FactoryBakery.bake(entry.resolve_target)
          value = parent.public_send(entry.natural_key_name)
          return if missing?(value)

          object.public_send("#{key}=", value)
          object.public_send("#{entry.name}=", parent)
        end

        def missing?(value)
          value.nil? || value.to_s.empty?
        end
      end
    end
  end
end
