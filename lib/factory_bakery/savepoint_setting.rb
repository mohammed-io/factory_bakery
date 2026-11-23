# frozen_string_literal: true

module FactoryBakery
  # The `FactoryBakery.savepoints` setting, extended onto the FactoryBakery
  # module.
  #
  # Whether the gem wraps the `bake!` envelope in a nested transaction (a
  # savepoint when the caller already holds a transaction). Off by default,
  # which is how factory_bot behaves: a failed `bake!` can leave the rows it
  # already wrote (a spec's own transaction cleans them up). Turn it on to
  # have them rolled back (ADR-0006).
  #
  # The setting switches the `bake!` wrapper only. The verified fallback's
  # attempts and the associations plugin's best-effort edges always keep
  # their savepoints: the fallback's rebuild re-runs declaration blocks, so
  # a parent the lean attempt saved must be rolled back, and on PostgreSQL
  # a failed statement outside a savepoint aborts the whole transaction.
  # Only targets whose mapper reports them as transactional are affected.
  module SavepointSetting
    def savepoints=(value)
      @savepoints = value ? true : false
    end

    def savepoints?
      @savepoints == true
    end
  end
end
