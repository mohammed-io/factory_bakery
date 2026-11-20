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

      # A shared primary key gives the callback row and the candidate the same
      # identity. Save the new owner first so its callback can claim that key.
      def callback_created_parent(parent, generated)
        ReflectionCache.all(parent.class).lazy.filter_map do |reflection|
          next unless shared_primary_key_owner?(parent, reflection)

          owner = parent.association(reflection.name).target
          next unless owner&.new_record? && generated.any? { |record| record.equal?(owner) }

          save_owner_and_find_parent(owner, parent, reflection)
        end.first
      end

      def save_owner_and_find_parent(owner, parent, reflection)
        inverse = owner.association(reflection.inverse_of.name)
        inverse.reset if inverse.target.equal?(parent)
        save!(owner)
        replacement = inverse.reload&.target
        return replacement if replacement.instance_of?(parent.class)

        parent.public_send("#{reflection.name}=", owner)
        nil
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
