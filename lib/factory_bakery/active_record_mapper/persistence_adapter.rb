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
        discarded = save_detaching_children!(owner, automatic)
        on_discard&.call(discarded)
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
      # matching the association and child's class wins; otherwise the child
      # is reattached. Returns the discarded children for core to unregister.
      def save_detaching_children!(record, automatic)
        children = []
        detach_autosave_children(record, automatic, children)
        save!(record)
        children.filter_map { |detached| settle_child(detached) }
      rescue StandardError
        children.each { |detached| reattach(detached) }
        raise
      end

      def detach_autosave_children(record, automatic, children)
        automatic = Set.new.compare_by_identity.merge(automatic)
        seen = Set.new.compare_by_identity
        pending = [record]
        until pending.empty?
          owner = pending.pop
          next unless seen.add?(owner)

          autosave_associations(owner).each do |association|
            child = association.target
            if !child.equal?(record) && detachable_child?(association, automatic)
              children << DetachedChild.new(owner:, reflection: association.reflection, child:)
              association.target = nil
            else
              pending.concat(autosave_targets(association))
            end
          end
        end
      end

      def autosave_associations(owner)
        ReflectionCache.all(owner.class).filter_map do |reflection|
          next if reflection.options[:autosave] == false || !owner.association_cached?(reflection.name)

          association = owner.association(reflection.name)
          next unless reflection.collection? || association.loaded?

          association unless association.stale_target?
        end
      end

      def autosave_targets(association)
        Array(association.target).select { |target| autosave_target?(association, target) }
      end

      def autosave_target?(association, target)
        reflection = association.reflection
        owner = association.owner
        autosave = reflection.options[:autosave]
        return false if target.destroyed? || (autosave && target.marked_for_destruction?)
        return autosave_collection_target?(owner, reflection, target) if reflection.collection?
        return true if autosave && target.changed_for_autosave?
        return true if target.new_record?
        return false unless reflection.macro == :has_one

        owner.send(:_record_changed?, reflection, target, owner_key(owner, reflection))
      end

      def autosave_collection_target?(owner, reflection, target)
        return target.changed_for_autosave? if reflection.options[:autosave] && !owner.new_record?
        return false if reflection.nested?
        return target.new_record? unless owner.new_record?

        !reflection.through_reflection? || target.new_record? || target.has_changes_to_save?
      end

      def detachable_child?(association, automatic)
        reflection = association.reflection
        return false unless reflection.macro == :has_one && !reflection.through_reflection?

        child = association.target
        child&.new_record? && !child.destroyed? &&
          !(reflection.options[:autosave] && child.marked_for_destruction?) &&
          automatic.include?(child) && optional_edge?(association.owner, reflection)
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
        reflection = detached.reflection
        replacement = owner.association(reflection.name).reload&.target if owner.persisted?
        return detached.child if replacement.instance_of?(detached.child.class) &&
                                 matching_child_key?(owner, reflection, replacement)

        reattach(detached)
        nil
      end

      def matching_child_key?(owner, reflection, child)
        keys = owner_key(owner, reflection)
        foreign_keys = Array(reflection.foreign_key).map { |key| child._read_attribute(key) }
        return false if keys.any?(&:nil?) || keys != foreign_keys

        !reflection.type || child._read_attribute(reflection.type) == owner.class.polymorphic_name
      end

      def owner_key(owner, reflection)
        Array(reflection.active_record_primary_key).map { |key| owner._read_attribute(key) }
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
