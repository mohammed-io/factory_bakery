# frozen_string_literal: true

module FactoryBakery
  module ActiveRecordMapper
    # The per-column database check behind the mapper's `uniqueness_check`:
    # the model's own uniqueness validator is asked against a probe copy of
    # the record, so scoping, case sensitivity, enum mapping and STI behave
    # exactly as they do on a real save. A column protected only by a unique
    # index has no validator, so the table is asked directly instead.
    module UniquenessProbe
      class << self
        # True when the attribute's value is already taken: any of the
        # validators reports a `:taken` error on the probe, or — with no
        # validator — the table itself holds the value under its unique index.
        def taken?(record, attr_name, value, validators)
          return unique_index_taken?(record, attr_name, value) if validators.empty?

          validators.any? do |validator|
            probe = build_probe(record, attr_name, value)
            validator.validate_each(probe, attr_name, value)
            taken_error?(probe.errors, attr_name)
          end
        end

        private

        # Does the database already hold `value` in a unique-indexed column? The
        # record's own class scopes the query like the index's table (default
        # scope and STI included); a persisted record never collides with itself.
        # The guard count mirrors the index's semantics (nil never matches,
        # a default scope would hide a row, a persisted row excludes itself),
        # so it moves here unchanged rather than being rewritten.
        # The guard count mirrors the index's semantics (nil never matches,
        # a default scope would hide a row, a persisted row excludes itself),
        # so it moves here unchanged rather than being rewritten.
        # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
        def unique_index_taken?(record, attr_name, value)
          klass = record.class
          return false if value.nil?
          return false unless klass.respond_to?(:where)

          # `unscoped` matches the database index (and Rails' own uniqueness
          # validator) instead of a default scope that could hide a row.
          scope = klass.respond_to?(:unscoped) ? klass.unscoped : klass
          scope = scope.where(attr_name => value)
          if record.respond_to?(:persisted?) && record.persisted? && klass.primary_key
            scope = scope.where.not(klass.primary_key => record.public_send(klass.primary_key))
          end
          scope.exists?
        rescue StandardError
          false
        end
        # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity

        def build_probe(record, attr_name, value)
          probe = duplicate(record)
          probe.public_send("#{attr_name}=", value) if probe.respond_to?("#{attr_name}=")
          probe.errors.clear if probe.respond_to?(:errors)
          probe
        end

        # `dup` runs the initialize callbacks, which raise on the models the
        # construction fallback exists for (issue #56). The validator only reads
        # attributes, so such a record is probed through a callback-free copy.
        def duplicate(record)
          record.dup
        rescue StandardError => e
          raise e unless Construction.callback_free_capable?(record.class)

          Construction.copy(record)
        end

        # `Errors#added?` does a strict options match, but the uniqueness
        # validator attaches the candidate as `value:`. `details` keeps just
        # the error kind.
        def taken_error?(errors, attr_name)
          details = errors.details[attr_name.to_sym] || errors.details[attr_name.to_s]
          Array(details).any? { |detail| detail[:error] == :taken }
        end
      end
    end
  end
end
