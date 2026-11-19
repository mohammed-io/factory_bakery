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
  class FallbackBuilder
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
      return build_without_savepoint(model_klass, definition, overrides, traits) unless savepoint_available?(adapter)

      mark = BuildContext.generated_records.length
      kept = nil
      discarded = false
      begin
        adapter.transaction(model_klass) do
          candidate, builder = build_object(model_klass, definition, overrides, traits, @mode)
          if fallback_needed?(candidate, builder)
            BuildContext.trim_generated_records!(mark)
            discarded = true
            raise DiscardAttempt
          end
          kept = candidate
        end
      rescue DiscardAttempt
        # The savepoint already rolled the lean attempt's writes back.
      end
      return kept unless discarded

      FillOptional.with(true) do
        adapter.transaction(model_klass) do
          rebuilt, = build_object(model_klass, definition, overrides, traits, true)
          rebuilt
        end
      end
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

    # A savepoint is only useful when a fallback can happen: with the opt-in
    # fully on, `fallback_needed?` is always false and there is nothing to
    # roll back. Non-transactional targets keep their plain build-and-save path.
    def savepoint_available?(adapter)
      adapter.transactional? && !FillOptional.full?(@mode)
    end

    def build_without_savepoint(model_klass, definition, overrides, traits)
      mark = BuildContext.generated_records.length
      object, builder = build_object(model_klass, definition, overrides, traits, @mode)
      return object unless fallback_needed?(object, builder)

      BuildContext.trim_generated_records!(mark)
      FillOptional.with(true) { build_object(model_klass, definition, overrides, traits, true).first }
    end

    def fallback_needed?(object, builder)
      return false if FillOptional.full?(@mode)
      return false unless builder.verification_needed?
      return false unless builder.optional_candidates?
      return false unless object.respond_to?(:valid?)

      # A validator that raises on the lean record (for example one that reads
      # an optional column we left nil) cannot certify it either, so the
      # fuller rebuild is the better answer. Never let the probe itself break
      # a bake that previously worked.
      !object.valid?
    rescue StandardError
      true
    end
  end
end
