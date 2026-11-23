# frozen_string_literal: true

module FactoryBakery
  # Saves the root record of a `bake!`, and when the save's own uniqueness
  # validation finds a value taken that the gem generated, regenerates that
  # value and saves again.
  #
  # The root record's uniqueness is not asked of the database while it is built
  # (UniquenessEnforcer#taken_in_database?): `save!` runs the same validator a
  # moment later, so the second query was pure repetition. This closes the
  # loop. Only a failure made up entirely of `:taken` errors on attributes the
  # gem generated is retried; an override, a declaration or any other error
  # fails the bake as before. A failed `save!` writes nothing of its own, so a
  # retry cannot duplicate a row.
  module UniquenessRetry
    class << self
      def save!(record, adapter)
        attempts = 0
        begin
          adapter.save!(record)
        rescue StandardError
          attempts += 1
          names = regenerable(record)
          raise if names.empty? || attempts >= UniquenessEnforcer::MAX_ATTEMPTS

          regenerate(record, names)
          retry
        end
      end

      private

      # The build-time check is back on: the root marker is only set while the
      # graph is built, so this one asks the database. The record is bound the
      # way it is while it is built, because a filler resolves its rules
      # against the live record.
      def regenerate(record, names)
        BuildContext.with_record(record) { UniquenessEnforcer.new(record, names).call }
        BuildContext.invalidate_condition_results!
      end

      # The generated attributes behind the failure, or none when anything else
      # is wrong with the record.
      def regenerable(record)
        origin = Provenance.of(record)
        details = error_details(record)
        return [] unless origin && !details.empty?
        return [] unless details.all? { |name, errors| generated_taken?(origin, name, errors) }

        details.keys.map(&:to_s)
      end

      def error_details(record)
        return {} unless record.respond_to?(:errors) && record.errors.respond_to?(:details)

        record.errors.details
      end

      def generated_taken?(origin, name, errors)
        origin.filled.include?(name.to_s) && errors.all? { |error| error[:error] == :taken }
      end
    end
  end
end
