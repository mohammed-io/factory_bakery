# frozen_string_literal: true

module FactoryBakery
  module Associations
    # Auto-builds has_one/has_many for :all after the owner exists. It reuses
    # TargetBuilder, the same machinery explicit declarations use, so a child
    # gets its scope attributes and verified inverse before its own auto-build
    # runs. Anything already decided by a declaration or override is skipped.
    # The association list itself comes from the mapper's introspection.
    module AllAutoBuilder # rubocop:disable Metrics/ModuleLength
      class << self # rubocop:disable Metrics/ClassLength
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

          return false if entry.through
          return false if habtm_join?(entry)

          true
        end

        # Rails' HABTM middle reflection (Post::HABTM_Tags) can reach the
        # plugin as a has_many in some versions. Its join model is anonymous
        # plumbing, never a child the user asked to bake.
        def habtm_join?(entry)
          name = entry.target_class_name.to_s.split('::').last
          return true if name&.start_with?('HABTM_')

          klass = entry.target.call
          klass.name&.start_with?('HABTM_')
        rescue StandardError
          false
        end

        def skip?(object, entry, declared)
          return true if declared.include?(entry.name)
          return true if object.association(entry.name.to_sym).loaded?
          return true if BelongsToBuilder.suppressed_edge?(object.class, entry.name)
          return true if skip_unverified_inverse?(object, entry)

          false
        end

        # Without a verified belongs_to inverse the child's create scope sets
        # the owner's id, which is still nil while the owner is unsaved. A
        # child that requires the owner would then fail with "Owner must
        # exist", so the edge is left unbuilt instead.
        def skip_unverified_inverse?(object, entry)
          return false if verified_inverse?(entry)

          required_back_reference?(object, entry)
        end

        def verified_inverse?(entry)
          name = call_safely(entry, :inverse_name)
          return false if name.nil?

          call_safely(entry, :inverse_kind) == :belongs_to
        end

        def call_safely(entry, callable)
          entry.public_send(callable).call
        rescue StandardError
          nil
        end

        def required_back_reference?(object, entry)
          target = entry.resolve_target
          introspection = FactoryBakery::MapperRegistry.association_introspection(target)
          return false unless introspection

          introspection.any? do |candidate|
            candidate.kind == :belongs_to && candidate.required && back_reference?(object, candidate)
          end
        rescue StandardError
          false
        end

        def back_reference?(object, candidate)
          object.is_a?(candidate.resolve_target)
        rescue StandardError
          false
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

          return build_optional_child(object, entry, declaration) if optional?(object, entry)

          build_required_child(object, entry, declaration)
        end

        def optional?(object, entry)
          return true if entry.kind == :has_many
          return false if entry.presence_applicable.call(object)

          true
        rescue StandardError
          false
        end

        def build_required_child(object, entry, declaration)
          if entry.kind == :has_many
            TargetBuilder.build_collection(object, declaration, entry)
          else
            object.public_send("#{entry.name}=", TargetBuilder.bake_child(object, declaration, entry))
          end
        end

        # :all builds optional collections and has_one children too, but a
        # child that cannot be baked (or is invalid) must not fail the whole
        # bake. Build it inside a savepoint; on any failure roll the child's
        # writes and generated records back and leave the edge empty/nil.
        def build_optional_child(object, entry, declaration)
          adapter = FactoryBakery::MapperRegistry.persistence_adapter(object.class)
          mark = BuildContext.generated_records.length
          begin
            if adapter.transactional?
              adapter.transaction(object.class) { build_and_validate(object, entry, declaration) }
            else
              build_and_validate(object, entry, declaration)
            end
          rescue StandardError
            BuildContext.trim_generated_records!(mark)
            discard_child(object, entry)
          end
        end

        def build_and_validate(object, entry, declaration)
          if entry.kind == :has_many
            TargetBuilder.build_collection(object, declaration, entry)
            children = object.public_send(entry.name).to_a
            raise FactoryBakery::FallbackBuilder::DiscardAttempt if children.any? { |child| invalid_child?(child) }
          else
            child = TargetBuilder.bake_child(object, declaration, entry)
            raise FactoryBakery::FallbackBuilder::DiscardAttempt if invalid_child?(child)

            object.public_send("#{entry.name}=", child)
          end
        end

        def invalid_child?(child)
          GraphValidity.invalid?(child)
        end

        def discard_child(object, entry)
          if entry.kind == :has_many
            association = object.association(entry.name.to_sym)
            association.target = []
            association.loaded!
          else
            object.public_send("#{entry.name}=", nil)
          end
        rescue StandardError
          nil
        end
      end
    end
  end
end
