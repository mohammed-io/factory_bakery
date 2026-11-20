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

          declared = Array(context.taken_names) + declarations.map { |declaration| declaration.name.to_s }
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
          return false unless foreign_keys_exist?(entry)

          true
        end

        # A declared association whose foreign key the target cannot store is
        # dead: Discourse's `Topic has_many :user_profiles`, whose table has no
        # `topic_id`. Building it would write an unknown attribute
        # (ActiveModel::MissingAttributeError). The column facts come from the
        # mapper, so the core never reads a schema itself.
        def foreign_keys_exist?(entry)
          target = entry.resolve_target

          entry.foreign_keys.all? { |key| FactoryBakery::MapperRegistry.column?(target, key) }
        rescue StandardError
          false
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

        # A has_many/has_one is skipped before its association proxy is touched
        # when its foreign key is not a column of the target class: reading the
        # proxy of such an edge raises "no such column" (Discourse's
        # `Topic has_many :user_profiles`), so the check belongs ahead of the
        # loaded? probe.
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

          return build_required_child(object, entry, declaration) unless optional?(object, entry)
          return defer_has_one(entry, declaration) if entry.kind == :has_one && BuildContext.persisting?

          build_optional_child(object, entry, declaration)
        end

        # Let the owner's save callbacks populate this edge first. The save
        # may also have cached nil before a callback inserted a row directly.
        def defer_has_one(entry, declaration)
          context = BuildContext.current
          fill_mode = FillOptional.nested_in_rebuild?(context.depth) ? false : FillOptional.current
          options = Associations::SCOPE_KEYS.to_h { |name| [name, Associations.public_send(name)] }
          context.defer_until_persisted do |persisted_owner|
            next if persisted_owner.association(entry.name.to_sym).target

            Associations.with(**options) do
              FillOptional.with(fill_mode) { build_optional_child(persisted_owner, entry, declaration, refresh: true) }
            end
          end
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
            TargetBuilder.build_collection(object, declaration, entry, automatic: true)
          else
            object.public_send("#{entry.name}=", TargetBuilder.bake_child(object, declaration, entry, automatic: true))
          end
        end

        # :all builds optional collections and has_one children too, but a
        # child that cannot be baked (or is invalid) must not fail the whole
        # bake. Build it inside a savepoint; on any failure roll the child's
        # writes and generated records back and leave the edge empty/nil.
        def build_optional_child(object, entry, declaration, refresh: false)
          adapter = FactoryBakery::MapperRegistry.persistence_adapter(object.class)
          mark = BuildContext.generated_records.length
          # A proc, not a lambda: the adapter's transaction may yield the
          # transaction object, which this block ignores.
          build = proc do
            next if refresh && object.association(entry.name.to_sym).reload

            build_and_validate(object, entry, declaration)
          end
          begin
            if adapter.transactional?
              adapter.transaction(object.class, &build)
            else
              build.call
            end
          rescue StandardError
            BuildContext.trim_generated_records!(mark)
            discard_child(object, entry, refresh)
          end
        end

        def build_and_validate(object, entry, declaration)
          if entry.kind == :has_many
            TargetBuilder.build_collection(object, declaration, entry, automatic: true)
            children = object.public_send(entry.name).to_a
            raise FactoryBakery::FallbackBuilder::DiscardAttempt if children.any? { |child| discardable?(child) }
          else
            child = TargetBuilder.bake_child(object, declaration, entry, automatic: true)
            raise FactoryBakery::FallbackBuilder::DiscardAttempt if discardable?(child)

            object.public_send("#{entry.name}=", child)
          end
        end

        # An optional child that cannot be written (Mastodon's `User has_many
        # :ips`, whose target `UserIp` is a database view) is discarded like an
        # invalid child: :all builds optional edges on a best-effort basis, and
        # the edge stays empty instead of failing the whole bake with
        # ReadOnlyTargetError. Required edges keep their behaviour.
        def discardable?(child)
          invalid_child?(child) || read_only_child?(child)
        end

        def read_only_child?(child)
          adapter = FactoryBakery::MapperRegistry.persistence_adapter(child)
          FactoryBakery::MapperRegistry.read_only?(child) && !adapter.persisted?(child)
        end

        def invalid_child?(child)
          GraphValidity.invalid?(child)
        end

        def discard_child(object, entry, refresh)
          return object.association(entry.name.to_sym).reset if refresh

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
