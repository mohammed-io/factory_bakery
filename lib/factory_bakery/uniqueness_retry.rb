# frozen_string_literal: true

module FactoryBakery
  # Saves the root record of a `bake!`, and when the save's own uniqueness
  # validation finds a deferred value taken, regenerates that value and saves
  # again.
  #
  # The retry is bounded three ways. It follows only a validation failure of
  # this very record (the adapter's `validation_failure?`): an adapter that
  # cannot tell never retries, and any other exception propagates untouched.
  # The failure must be made up entirely of `:taken` errors on attributes
  # whose check was actually deferred to the save (Provenance.deferred) -- a
  # value the caller chose, one already checked while building, or any other
  # kind of error is never regenerated. And when a failed save reports the
  # same taken values as the one before it, no regeneration can help (a
  # `before_validation` rewriting the value back), so the error is raised
  # instead of looping. A failed `save!` writes nothing of its own, so a
  # retry cannot duplicate a row.
  module UniquenessRetry
    class << self
      def save!(record, adapter)
        attempts = 0
        previous_taken = nil
        begin
          adapter.save!(record)
        rescue StandardError => e
          attempts += 1
          raise if attempts >= UniquenessEnforcer::MAX_ATTEMPTS
          raise unless own_validation_failure?(adapter, e, record)

          taken = taken_values(record)
          names = regenerable(record)
          raise if taken == previous_taken || names.empty?

          previous_taken = taken
          regenerate(record, names)
          retry
        end
      end

      private

      # True only when the adapter says `error` is a validation failure of
      # this record. Adapters without the notion (Sequel, the null adapter)
      # never retry; the original error is raised untouched.
      def own_validation_failure?(adapter, error, record)
        return false unless adapter.respond_to?(:validation_failure?)

        adapter.validation_failure?(error, record)
      end

      # The `:taken` values the save reported, keyed by attribute: the
      # progress check compares these between consecutive failed saves.
      def taken_values(record)
        error_details(record).transform_values do |errors|
          errors.filter_map { |error| error[:value] if error[:error] == :taken }
        end
      end

      # The attributes behind the failure, or none when anything else is wrong
      # with the record: every error attribute must carry only `:taken`
      # errors and must be one whose check was deferred to the save.
      def regenerable(record)
        deferred = Provenance.deferred(record)
        details = error_details(record)
        return [] if details.empty?
        return [] unless details.all? do |name, errors|
          deferred.include?(name.to_s) && errors.all? { |error| error[:error] == :taken }
        end

        details.keys.map(&:to_s)
      end

      def error_details(record)
        return {} unless record.respond_to?(:errors) && record.errors.respond_to?(:details)

        record.errors.details
      end

      # The build-time check is back on: the root marker is only set while the
      # graph is built, so this one asks the database. The record is bound the
      # way it is while it is built, because a filler resolves its rules
      # against the live record.
      def regenerate(record, names)
        BuildContext.with_record(record) { UniquenessEnforcer.new(record, names).call }
        BuildContext.invalidate_condition_results!
      end
    end
  end
end
