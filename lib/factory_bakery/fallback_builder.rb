# frozen_string_literal: true

module FactoryBakery
  # ADR-0002 verification for required-only bakes: try the lean record first,
  # then rebuild once with optional columns filled if it is invalid. Each
  # attempt runs in its own savepoint through the mapper's persistence adapter,
  # so a declaration block (or a FK-presence parent) that writes during a lean
  # attempt is rolled back before the rebuild. The rebuild runs with the opt-in
  # scoped on, so nested parents built by declarations use the same rule and
  # never run a second fallback. Declaration blocks may therefore run twice
  # when the fallback triggers.
  #
  # A record built with optional fills is verified against them too. A column
  # guarded only by a custom validator (or a `validate` block) can receive a
  # value the heuristics cannot know is wrong, so an optional fill that carries
  # a validation error is put back to its column default (or nil) when that
  # makes the record valid. A required-only lean record that is already valid
  # is never probed.
  class FallbackBuilder # rubocop:disable Metrics/ClassLength
    # Raised inside an attempt's savepoint to discard that attempt. The
    # adapter's transaction rolls back on any exception and re-raises it; the
    # core catches its own signal, so it never names a framework rollback
    # constant (ADR-0001).
    class DiscardAttempt < StandardError; end

    def initialize(mode)
      @mode = mode
    end

    def build(model_klass, definition, overrides, traits)
      adapter = MapperRegistry.persistence_adapter(model_klass)
      unless savepoint_available?(adapter, model_klass)
        return build_without_savepoint(model_klass, definition, overrides, traits)
      end

      attempt, probe, errors = attempt_in_savepoint(model_klass, definition, overrides, traits, adapter)
      return verify_optional_fills!(attempt, probe) unless probe == :invalid

      verify_rebuild!(rebuild(model_klass, definition, overrides, traits, adapter, errors))
    end

    def build_object(model_klass, definition, overrides, traits, mode)
      builder = BakeryBuilder.new(model_klass, definition, fill_optional: mode)
      object = builder.build(overrides: overrides, traits: traits)
      BuildContext.with_record(object) do
        UniquenessEnforcer.new(object, builder.heuristic_attribute_names).call
      end
      BuildContext.record_generated(object)
      [object, builder]
    end

    private

    # The lean attempt in its own savepoint, with the probe that decides
    # whether it is kept. A :invalid probe means the attempt was discarded and
    # its writes rolled back; the attempt is still returned because its builder
    # is the one that knows which fills were optional. The error names the
    # probe saw are returned with it, read while the lean record still carried
    # them.
    def attempt_in_savepoint(model_klass, definition, overrides, traits, adapter)
      mark = BuildContext.generated_records.length
      attempt = nil
      probe = nil
      errors = []
      begin
        adapter.transaction(model_klass) do
          attempt = build_object(model_klass, definition, overrides, traits, @mode)
          probe = fallback_probe(*attempt)
          errors = missing_attributes(attempt.first) if probe == :invalid
          if probe == :invalid
            BuildContext.trim_generated_records!(mark)
            raise DiscardAttempt
          end
        end
      rescue DiscardAttempt
        # The savepoint already rolled the lean attempt's writes back.
      end
      [attempt, probe, errors]
    end

    # The rebuild, with the opt-in scoped on. It answers a lean record that was
    # already probed and found invalid. The opt-in applies only to the record
    # being rebuilt: a nested bake (a parent built by a declaration or
    # association) is a separate record with its own fallback and stays lean, so
    # the rebuild cannot turn a nested parent into a fuller record that fails its
    # own validation. The rebuilt record is verified by the caller, which puts
    # back any virtual optional fill a custom validation rejects.
    #
    # The lean probe's error names travel with the rebuild (fiber-local, like
    # the depth): an optional belongs_to those errors blamed is built like a
    # required edge, because a custom validator demands it even though no
    # discovered constraint does (Discourse's `PostValidator`). `probe_errors`
    # are the names read while the lean record still carried them, because
    # `valid?` clears `errors` on its next run.
    def rebuild(model_klass, definition, overrides, traits, adapter, probe_errors)
      with_rebuild_errors(probe_errors) do
        transaction(adapter, model_klass) do
          build_object(model_klass, definition, overrides, traits, true)
        end
      end
    end

    def with_rebuild_errors(names, &block)
      FillOptional.with_rebuild(BuildContext.current.depth, error_attributes: names, &block)
    end

    # A mapper whose targets open no transactions has no savepoint to rebuild
    # in; the plain build is the same thing without one.
    def transaction(adapter, model_klass, &block)
      return block.call unless adapter.transactional?

      adapter.transaction(model_klass, &block)
    end

    # A savepoint is only useful when a fallback can happen: with the opt-in
    # fully on, `fallback_probe` never asks for a rebuild and there is nothing
    # to roll back. Non-transactional targets keep their plain build-and-save
    # path.
    def savepoint_available?(adapter, model_klass)
      adapter.transactional? && !FillOptional.full?(@mode) && fallback_possible?(model_klass)
    end

    # The fallback can only trigger when verification can be needed: the
    # mapper cannot read all of the class's validation logic, or some column
    # pairs a default with validators. Read without a bound record, so
    # conditional validators count as present (a superset, never a miss).
    # A class that cannot even be introspected here is left to construction,
    # which reports its own error, so assume the fallback is possible.
    def fallback_possible?(model_klass)
      MapperRegistry.custom_validation?(model_klass) ||
        MapperRegistry.attribute_universe(model_klass).any? do |name|
          constraints = MapperRegistry.constraints_for(model_klass, name)
          constraints.has_default && constraints.has_validators
        end
    rescue StandardError
      true
    end

    def build_without_savepoint(model_klass, definition, overrides, traits)
      adapter = MapperRegistry.persistence_adapter(model_klass)
      mark = BuildContext.generated_records.length
      object, builder = build_object(model_klass, definition, overrides, traits, @mode)
      attempt = [object, builder]
      probe = fallback_probe(object, builder)
      return verify_optional_fills!(attempt, probe) unless probe == :invalid

      BuildContext.trim_generated_records!(mark)
      errors = missing_attributes(object)
      verify_rebuild!(rebuild(model_klass, definition, overrides, traits, adapter, errors))
    end

    # :invalid when the lean record must be rebuilt, :valid when the probe
    # certified it, nil when no probe was needed. A nil probe is what lets the
    # optional-fill verification below run its own `valid?` without repeating
    # one the caller already paid for.
    def fallback_probe(object, builder)
      return nil if FillOptional.full?(@mode)
      return nil unless builder.verification_needed?
      return nil unless builder.optional_candidates?
      return nil unless object.respond_to?(:valid?)

      # A validator that raises on the lean record (for example one that reads
      # an optional column we left nil) cannot certify it either, so the
      # fuller rebuild is the better answer. Never let the probe itself break
      # a bake that previously worked.
      valid?(object) ? :valid : :invalid
    end

    # A rebuild answers a lean record that was probed and found invalid, so it
    # is normally returned as built. It is verified only when it filled a
    # virtual (non-column-backed) optional attribute: such a value is the one
    # the heuristics cannot validate against the schema, and the custom
    # validator that rejects it may name :base or another attribute rather than
    # the filled one (Discourse's LlmModel#requested_vision_mode is exactly
    # this shape). A rebuild of only column-backed optionals is already known
    # valid, so it is returned without another `valid?`.
    def verify_rebuild!(attempt)
      object, builder = attempt
      return object unless builder.verification_needed?
      return object unless builder.optional_candidates?
      return object unless builder.optional_candidates.any? { |name| virtual_optional?(object, name) }

      verify_optional_fills!(attempt, nil)
    end

    def virtual_optional?(object, name)
      !MapperRegistry.constraints_for(object.class, name).column_backed
    rescue StandardError
      false
    end

    # Undo optional fills that app validation rejects: an optional column
    # carries a generated value, a custom validator adds an error, and the
    # record the caller gets back would be invalid. A custom validator can add
    # that error to :base or to another attribute rather than to the filled one
    # (for example a virtual inclusion attribute whose value a `validate` block
    # rejects), so every optional fill is tried, not just the ones whose own
    # attribute carries an error. Each fill is put back to its column default
    # and kept only when that makes the record valid with fewer errors;
    # otherwise the generated value is restored, so a reset is never a
    # regression.
    def verify_optional_fills!(attempt, probe)
      object, builder = attempt
      return object unless builder.verification_needed?
      return object unless builder.optional_candidates?
      return object if probe == :valid
      return object if valid?(object)

      errored = error_attributes(object)
      candidates = builder.optional_candidates
      (candidates.select { |name| errored.include?(name) } + (candidates - errored)).each do |name|
        reset_optional_fill(object, name)
      end
      object
    end

    # Restore the generated value when the default does not help (or the
    # revalidation itself raises), so a reset is never a regression.
    def reset_optional_fill(object, name)
      setter = "#{name}="
      return unless object.respond_to?(setter)

      generated = object.public_send(name) if object.respond_to?(name)
      errors_before = object.errors.size
      assign(object, name, column_default(object, name))
      return if valid?(object) && object.errors.size < errors_before

      assign(object, name, generated)
      valid?(object)
    end

    # A record with no `valid?` is taken as valid: there is nothing to verify
    # against. A validator that raises cannot certify a record either, so it
    # counts as invalid -- and the probe never breaks a bake.
    def valid?(object)
      return true unless object.respond_to?(:valid?)

      object.valid?
    rescue StandardError
      false
    end

    def missing_attributes(object)
      return [] unless object.errors.respond_to?(:details)

      object.errors.details.filter_map do |name, errors|
        name if errors.any? { |error| missing_error?(error[:error]) }
      end
    end

    # Only "missing" errors direct the rebuild: an invalid or taken value is
    # not fixed by building the parent. Custom validators often add the
    # message as a String instead of the :blank / :required symbol.
    MISSING_MESSAGES = ["can't be blank", 'must exist'].freeze
    private_constant :MISSING_MESSAGES

    def missing_error?(error)
      return %i[blank required].include?(error) if error.is_a?(Symbol)

      MISSING_MESSAGES.include?(error.to_s)
    end

    # The attribute names an errors object carries, as strings: one that
    # exposes `attribute_names` (or `details`) is read through those, and a
    # Hash-like errors object through `keys`.
    def error_attributes(object)
      errors = object.errors
      names = if errors.respond_to?(:attribute_names)
                errors.attribute_names
              elsif errors.respond_to?(:details)
                errors.details.keys
              elsif errors.respond_to?(:keys)
                errors.keys
              end
      Array(names).map(&:to_s)
    end

    def column_default(object, name)
      constraints = MapperRegistry.constraints_for(object.class, name)
      constraints.has_default ? constraints.default_value : nil
    end

    def assign(object, name, value)
      setter = "#{name}="
      return unless object.respond_to?(setter)

      # Conditions read live attributes, so a cached result from before the
      # reset no longer describes the record.
      BuildContext.invalidate_condition_results!
      object.public_send(setter, value)
    end
  end
end
