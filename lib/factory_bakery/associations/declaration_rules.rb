# frozen_string_literal: true

module FactoryBakery
  module Associations
    # Bake-time checks that a declaration's options fit the association it
    # names. They run at bake time, not definition time, so factories can load
    # before the models they name.
    module DeclarationRules
      class << self
        def validate!(object, declaration, entry)
          if unsupported_shape?(entry)
            raise FactoryBakery::Error,
                  "#{object.class}##{entry.name} (#{entry.kind}) is not supported; " \
                  'assign via an attribute block'
          end
          validate_strategy!(declaration, entry)
          validate_persist!(declaration, entry)
          return if declaration.child_count.nil? || collection?(entry)

          raise ArgumentError,
                "count: is only supported on collections, but #{object.class}##{entry.name} " \
                "is a #{entry.kind} association"
        end

        private

        # A has_one/has_many child needs the owner's id, so it cannot be saved
        # before the owner; only a parent can.
        def validate_persist!(declaration, entry)
          return if !declaration.persist || entry.kind == :belongs_to

          raise ArgumentError,
                "persist: is only supported on belongs_to, but #{qualified(entry)} is a #{entry.kind} association"
        end

        # Reusing a child would rewrite its FK and steal it from another
        # owner, so only an *explicit* :reuse_non_unique on a non-belongs_to
        # edge raises. An inherited scoped/global choice just skips ineligible
        # edges.
        def validate_strategy!(declaration, entry)
          return unless ReuseResolver.strategy_for(declaration) == :reuse_non_unique

          if declaration.strategy == :reuse_non_unique && entry.kind != :belongs_to
            raise ArgumentError,
                  "strategy: :reuse_non_unique is only supported on belongs_to, but #{qualified(entry)} " \
                  "is a #{entry.kind} association"
          end
          return unless entry.kind == :belongs_to
          return if declaration.traits.empty?

          raise ArgumentError,
                "traits cannot be combined with strategy: :reuse_non_unique on #{qualified(entry)}"
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
      end
    end
  end
end
