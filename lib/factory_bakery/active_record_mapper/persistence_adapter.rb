# frozen_string_literal: true

module FactoryBakery
  module ActiveRecordMapper
    # Persistence semantics for schema-backed records, exposed as plain
    # duck-typed methods so the core never touches the framework directly.
    #
    # `transaction` opens with requires_new, which becomes a savepoint when
    # the caller already holds a transaction: a failure rolls back every row
    # this bake wrote without disturbing the caller's transaction. `save!`
    # and `persisted?` are checked with respond_to? so foreign records inside
    # one bake graph (a plain object baked from a declaration) behave exactly
    # as before.
    module PersistenceAdapter
      module_function

      def transactional?
        true
      end

      # A savepoint relative to the caller's transaction, when there is one.
      def transaction(klass, &block)
        klass.transaction(requires_new: true, &block)
      end

      def save!(record)
        record.save! if record.respond_to?(:save!)
      end

      def read_only_parent(parent, owner, entry)
        klass = parent.class
        relation = klass.all
        reflection = ReflectionCache.all(owner.class).find { |edge| edge.name.to_s == entry.name }
        return unless reflection
        return if reflection.scope && !reflection.scope.arity.zero?

        relation = reflection.scope_for(relation, owner) if reflection.scope
        row = relation.reorder(klass.primary_key).first
        row if row.instance_of?(klass)
      end

      # A shared primary key gives the callback row and the candidate the same
      # identity. Save the new owner first so its callback can claim that key.
      def callback_created_parent(parent, generated, &on_discard)
        ReflectionCache.all(parent.class).lazy.filter_map do |reflection|
          next unless shared_primary_key_owner?(parent, reflection)

          owner = parent.association(reflection.name).target
          next unless owner&.new_record? && generated.any? { |record| record.object.equal?(owner) }

          save_owner_and_find_parent(owner, parent, reflection, automatic_objects(generated), &on_discard)
        end.first
      end

      def save_owner_and_find_parent(owner, parent, reflection, automatic, &on_discard)
        inverse = owner.association(reflection.inverse_of.name)
        inverse.reset if inverse.target.equal?(parent)
        save_detaching_children!(owner, automatic).each { |child| on_discard&.call(child) }
        parent.public_send("#{reflection.name}=", owner)
        replacement = inverse.reload&.target
        return replacement if replacement.instance_of?(parent.class) && replacement.id == parent.id

        nil
      end

      # An automatic optional has_one child detached from its owner for a save.
      DetachedChild = Data.define(:owner, :reflection, :child)

      # Autosave inserts a new has_one child together with its owner, and an
      # owner callback that creates the same row would then collide with it.
      # The gem's automatic optional children are detached for the save. A row
      # the callback created wins; otherwise the child is reattached, unsaved,
      # to its owner. Required and user-declared children are never touched.
      # The save also autosaves the record's new parents and children (an
      # unsaved optional `belongs_to :deleted_by` User, say), so every new
      # record reachable through the loaded graph is covered, not only `record`.
      # Returns the children it dropped so the caller can unregister them; the
      # generated-record registry belongs to core, not to this adapter.
      def save_detaching_children!(record, automatic)
        children = unsaved_graph(record).flat_map { |owner| detachable_children(owner, automatic) }
        children.each { |detached| detached.owner.association(detached.reflection.name).target = nil }
        begin
          save!(record)
        rescue StandardError
          children.each { |detached| reattach(detached) }
          raise
        end
        children.filter_map { |detached| settle_child(detached) }
      end

      # `record` plus every new record reachable from it through loaded
      # associations: the records a save of `record` can autosave.
      def unsaved_graph(record)
        seen = Set.new.compare_by_identity
        pending = [record]
        until pending.empty?
          node = pending.pop
          next unless seen.add?(node)

          pending.concat(cached_association_targets(node).select { |target| target.respond_to?(:new_record?) && target.new_record? })
        end
        seen.to_a
      end

      def detachable_children(owner, automatic)
        ReflectionCache.all(owner.class).filter_map do |reflection|
          next unless reflection.macro == :has_one && optional_edge?(owner, reflection)

          child = owner.association(reflection.name).target
          next unless child&.new_record? && automatic.any? { |record| record.equal?(child) }

          DetachedChild.new(owner:, reflection:, child:)
        end
      end

      # An edge whose presence cannot be decided is treated as required, so it
      # is never detached: a detached required child would fail the owner's save.
      def optional_edge?(owner, reflection)
        !AssociationRequirements.presence_applicable?(owner.class, reflection, owner)
      rescue StandardError
        false
      end

      # The dropped child when the owner's callback created the row, else nil.
      # An owner the save did not reach is still new: nothing to look up.
      def settle_child(detached)
        owner = detached.owner
        return detached.child if owner.persisted? && owner.association(detached.reflection.name).reload

        reattach(detached)
        nil
      end

      def reattach(detached)
        detached.owner.association(detached.reflection.name).target = detached.child
      end

      def automatic_objects(generated)
        generated.select(&:automatic).map(&:object)
      end

      def shared_primary_key_owner?(parent, reflection)
        reflection.macro == :belongs_to && !reflection.polymorphic? &&
          Array(reflection.foreign_key) == Array(parent.class.primary_key) &&
          reflection.inverse_of&.macro == :has_one
      end

      def persisted?(record)
        !record.respond_to?(:new_record?) || !record.new_record?
      end

      def automatic_parent_discarded?(edge)
        owner = edge.owner
        return false unless owner.persisted?

        association = owner.association(edge.entry.name.to_sym)
        return true if optional_parent_cleared?(edge.entry, association, owner)
        return false if association.target.equal?(edge.parent) && !association.stale_target?

        persisted_replacement?(edge, association)
      end

      def optional_parent_cleared?(entry, association, owner)
        return false if entry.required || entry.fk_presence
        return false unless association.loaded? && association.target.nil?

        entry.foreign_keys.all? { |key| owner[key].nil? && !owner.will_save_change_to_attribute?(key) }
      end

      def persisted_replacement?(edge, association)
        return false unless foreign_key_persisted?(edge)

        replacement = association.reader
        replacement&.persisted? && !replacement.equal?(edge.parent)
      end

      def foreign_key_persisted?(edge)
        owner = edge.owner
        keys = [*edge.entry.foreign_keys, edge.entry.foreign_type].compact
        keys.all? { |key| !owner[key].nil? && !owner.will_save_change_to_attribute?(key) }
      end

      def cached_association_targets(record)
        return [] unless record.respond_to?(:association_cached?)

        ReflectionCache.all(record.class).flat_map do |reflection|
          next [] unless record.association_cached?(reflection.name)

          association = record.association(reflection.name)
          association.stale_target? ? [] : Array(association.target)
        end
      end

      # Best-effort name of the association the record hangs off. The object
      # graph is the source of truth here, so this also works for records
      # supplied through call-site overrides rather than declaration blocks.
      def association_name_for(record, candidates)
        candidates.each do |object|
          next unless object.class.respond_to?(:reflect_on_all_associations)

          name = association_on(object, record)
          return name if name
        end
        nil
      end

      def association_on(object, record)
        ReflectionCache.all(object.class).each do |reflection|
          next unless object.respond_to?(reflection.name)

          value = associated_value(object, reflection.name)
          next if value.nil?

          candidates = value.respond_to?(:target) ? value.target : [value]
          return reflection.name.to_s if Array(candidates).any? { |candidate| candidate.equal?(record) }
        end
        nil
      end

      def associated_value(object, name)
        object.public_send(name)
      rescue StandardError
        nil
      end

      # Read-only is a property of the record, not the class: models over
      # database views define `readonly?` as true on every instance, while a
      # single record can be marked read-only after loading. Both are refused
      # by bake! and left alone by bake.
      def read_only?(record)
        record.respond_to?(:readonly?) && record.readonly?
      end
    end
  end
end
