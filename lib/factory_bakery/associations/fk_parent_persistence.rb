# frozen_string_literal: true

module FactoryBakery
  module Associations
    # Raw-FK presence edges (`validates :user_id, presence: true`) cannot be
    # satisfied by an unsaved parent: its id is nil, so the FK stays nil. This
    # is the one shared decision point for auto-built and explicitly declared
    # belongs_to targets: give the target a real id by persisting it through
    # the mapper's persistence adapter, before the owner is validated.
    #
    # Under `bake!` the insert happens while the root savepoint is open, so it
    # rolls back atomically with every other row the bake wrote. Under plain
    # `bake` it is a documented exception to the unsaved contract: the row is
    # inserted outside any transaction. A `:reuse` miss under `bake` raises
    # instead, because that strategy promises not to write on a miss.
    #
    # Association-presence edges are deliberately untouched: an unsaved parent
    # satisfies `validates :user, presence: true`, so they stay database-free
    # under `bake`. Polymorphic edges keep their existing behavior too.
    module FkParentPersistence
      class << self
        def required?(entry)
          !entry.nil? && entry.fk_presence && !entry.polymorphic
        end

        # Called after a `:reuse` lookup misses. Under `bake` a fresh build
        # would have to be inserted to give the FK a value, which the reuse
        # contract does not allow; fail with the edge and the two ways out.
        def raise_on_reuse_miss!(source_class, entry)
          return unless required?(entry)
          return if BuildContext.persisting?

          column = entry.foreign_keys.first
          raise FactoryBakery::Error,
                "#{source_class}##{entry.name} validates foreign key #{column.inspect}, " \
                'but strategy: :reuse found no row to reuse under `bake`. ' \
                'Use `bake!` to create the parent atomically, declare the edge ' \
                "(e.g. association :#{entry.name}, strategy: :fresh), or pass " \
                "#{entry.name}: / #{column}: explicitly."
        end

        def persist!(parent, entry)
          return parent unless required?(entry)
          return parent unless parent.respond_to?(:new_record?) && parent.new_record?

          adapter = FactoryBakery::MapperRegistry.persistence_adapter(parent)
          adapter.save!(parent)
          parent
        end
      end
    end
  end
end
