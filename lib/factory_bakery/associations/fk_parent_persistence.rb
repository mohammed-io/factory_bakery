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
    # inserted outside any transaction. A `:reuse_non_unique` miss (or a unique
    # edge) builds the parent exactly like `:fresh` does under the same mode.
    #
    # A read-only parent (a model whose `readonly?` is true, e.g. a database
    # view) can never be inserted. The edge adopts an existing row of exactly
    # that class when the table has one; otherwise the parent stays unsaved and
    # no write is attempted. Under `bake!` that holds for every belongs_to
    # parent, not just FK-presence edges: a read-only parent the root `save!`
    # would autosave is replaced by an existing row, so the read-only guard
    # sees a persisted record (or fails the bake with `ReadOnlyTargetError`
    # when the table has no row). Under plain `bake` a read-only parent on a
    # non-FK edge stays unsaved and populated, and no database read happens.
    #
    # Association-presence edges are otherwise deliberately untouched: an
    # unsaved parent satisfies `validates :user, presence: true`, so they stay
    # database-free under `bake`. Polymorphic edges keep their existing
    # behavior too.
    module FkParentPersistence
      # Carries the replacement out of the savepoint after the fresh build rolls back.
      class AdoptedParent < StandardError
        attr_reader :row

        def initialize(row)
          @row = row
          super()
        end
      end

      class << self
        def required?(entry)
          !entry.nil? && entry.fk_presence && !entry.polymorphic
        end

        # Adopting a row discards the entire fresh build, including writes
        # made by nested declarations or FK-presence edges.
        def build(klass, entry)
          return yield unless required?(entry) || BuildContext.persisting?

          adapter = FactoryBakery::MapperRegistry.persistence_adapter(klass)
          mark = BuildContext.generated_records.length
          adapter.transaction(klass) { settle_fresh(yield, entry, mark) }
        rescue AdoptedParent => e
          BuildContext.trim_generated_records!(mark)
          e.row.reload
        end

        # Returns the parent that should be assigned to the owner: the object
        # it was given, the row it saved, or the existing row a read-only
        # parent adopted. `bake!` (`BuildContext.persisting?`) settles every
        # read-only new parent so the root save! never autosaves one; plain
        # `bake` only settles read-only parents on FK-presence edges, where
        # the id is needed.
        def settle(parent, entry)
          return adopt(parent) if read_only_new?(parent, entry)

          persist_fk!(parent, entry)
        end

        private

        def settle_fresh(parent, entry, mark)
          if read_only_new?(parent, entry)
            settled = adopt(parent)
            raise AdoptedParent, settled unless parent.equal?(settled)

            return parent
          end

          persist_fk!(parent, entry) do |adapter|
            next unless adapter.respond_to?(:callback_created_parent)

            generated = BuildContext.generated_records.drop(mark).map { |_path, record| record }
            adapter.callback_created_parent(parent, generated)
          end
        end

        def read_only_new?(parent, entry)
          new_record?(parent) &&
            FactoryBakery::MapperRegistry.read_only?(parent) &&
            (required?(entry) || BuildContext.persisting?)
        end

        def persist_fk!(parent, entry)
          return parent unless required?(entry) && new_record?(parent)

          refuse_broken_parents!(parent)
          adapter = FactoryBakery::MapperRegistry.persistence_adapter(parent)
          replacement = yield adapter if block_given?
          if replacement
            BuildContext.replace_generated!(parent, replacement)
            return replacement
          end

          adapter.save!(parent)
          parent
        end

        # Saving would let autosave skip an invalid unsaved parent and insert
        # this one with a nil foreign key (a NOT NULL violation, or a dangling
        # row). Fail with the real cause instead, so an optional edge is
        # discarded and a required one names what needs a definition.
        def refuse_broken_parents!(parent)
          broken = GraphValidity.first_invalid_parent(parent)
          return unless broken

          raise FactoryBakery::Error,
                "#{parent.class} cannot be inserted: its required #{broken.class} is invalid " \
                "(#{Array(broken.errors.full_messages).first(3).join('; ')})"
        end

        def new_record?(parent)
          parent.respond_to?(:new_record?) && parent.new_record?
        end

        # A read-only parent is never saved: an existing row of exactly that
        # class is adopted so the FK points somewhere real, and an empty table
        # leaves the parent unsaved rather than raising here.
        def adopt(parent)
          row = persisted_row(parent)
          return parent unless row

          BuildContext.replace_generated!(parent, row)
          row
        end

        def persisted_row(parent)
          klass = parent.class
          return nil unless klass.respond_to?(:all) && klass.respond_to?(:primary_key)

          klass.reorder(klass.primary_key).first
        rescue StandardError
          nil
        end
      end
    end
  end
end
