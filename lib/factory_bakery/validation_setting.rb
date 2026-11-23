# frozen_string_literal: true

module FactoryBakery
  # The `FactoryBakery.validate` setting, extended onto the FactoryBakery
  # module.
  #
  # Whether the gem runs its own checks during a bake. On (the default) a bake
  # is verified: the verified fallback probes a lean record with `valid?`,
  # rebuilds once when the probe says invalid, verifies optional fills, and
  # the build-time uniqueness checks run (database queries and the in-bake
  # registry). Off, values are still generated from the validators and column
  # types exactly as before, but the gem checks nothing, like
  # `FactoryBot.build`: a bake may return an invalid record. `bake!` still
  # saves through the framework's normal validation, so an invalid record
  # still raises there.
  #
  # Not switched by this option: the associations plugin's best-effort
  # validity checks of optional children, which are part of that plugin's own
  # strategy, keep running.
  module ValidationSetting
    class << self
      # Raises ArgumentError unless the value is a valid `validate` setting:
      # true, false, or nil (which means true, the default).
      def check(value)
        return value if value.nil? || value == true || value == false

        raise ArgumentError, "validate must be true or false, got #{value.inspect}"
      end
    end

    # Sets the global value: true, false or nil (nil means true).
    def validate=(value)
      ValidationSetting.check(value)
      @validate = value.nil? || value
    end

    # The effective value: a per-call `validate:` if one is active, else the
    # global setting, true by default.
    def validate?
      override = Verification.override
      return override unless override.nil?

      @validate != false
    end
  end
end
