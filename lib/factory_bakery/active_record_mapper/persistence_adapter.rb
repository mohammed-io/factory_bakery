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
      def transaction(klass)
        klass.transaction(requires_new: true) { yield }
      end

      def save!(record)
        record.save! if record.respond_to?(:save!)
      end

      def persisted?(record)
        !record.respond_to?(:new_record?) || !record.new_record?
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
    end
  end
end
