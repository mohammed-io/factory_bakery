# frozen_string_literal: true

module FactoryBakery
  # The `FactoryBakery.savepoints` setting, extended onto the FactoryBakery
  # module.
  #
  # Whether the gem wraps its own all-or-nothing envelopes in a nested
  # transaction (a savepoint when the caller already holds a transaction): the
  # `bake!` wrapper and the verified fallback's attempts. Off by default, which
  # is how factory_bot behaves: a failed `bake!` or a discarded fallback
  # attempt can leave the rows it already wrote (a spec's own transaction
  # cleans them up). Turn it on to have them rolled back (ADR-0006).
  #
  # The associations plugin's best-effort edges keep their savepoints either
  # way: they rescue a failed child and carry on, and on PostgreSQL a failed
  # statement outside a savepoint would poison the whole transaction. Only
  # targets whose mapper reports them as transactional are affected.
  module SavepointSetting
    def savepoints=(value)
      @savepoints = value ? true : false
    end

    def savepoints?
      @savepoints == true
    end
  end
end
