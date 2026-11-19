# frozen_string_literal: true

module FactoryBakery
  module Sequel
    # Persistence semantics for Sequel::Model records, exposed as plain
    # duck-typed methods so the core never touches the framework directly.
    #
    # Differences from the default mapper's adapter, documented rather than
    # smoothed over:
    #   * Sequel has no bang `save!`; its `save` already raises
    #     Sequel::ValidationFailed (or a hook failure) on failure by default
    #     (`raise_on_save_failure`), so save! maps to `save` for Sequel
    #     records and keeps honoring `save!` on foreign records that have
    #     one.
    #   * `transaction` opens `db.transaction(savepoint: true)`: a
    #     savepoint when the caller already holds a transaction, a plain
    #     transaction otherwise -- the same failure isolation the default
    #     mapper provides through its own require-new wrapper.
    #   * Records answer `new?` instead of the default mapper's
    #     `new_record?`; persisted? maps accordingly.
    module PersistenceAdapter
      module_function

      def transactional?
        true
      end

      # A savepoint relative to the caller's transaction, when there is one.
      def transaction(klass, &block)
        klass.db.transaction(savepoint: true, &block)
      end

      def save!(record)
        return record.save! if record.respond_to?(:save!)

        record.save if record.respond_to?(:save)
      end

      def persisted?(record)
        !record.respond_to?(:new?) || !record.new?
      end

      # Association naming stays out of scope for this mapper: the
      # associations plugin's orchestration is a primary-framework feature,
      # so verification errors simply name the record's class.
      def association_name_for(_record, _candidates)
        nil
      end
    end
  end
end
