# frozen_string_literal: true

module FactoryBakery
  module Associations
    # Translates the Railtie's `config.factory_bakery.associations` value into
    # plugin settings. This lives with the plugin, not the Railtie, so key
    # validation stays with the code that owns the settings. Value validation
    # is already done by the public setters.
    module RailConfig
      class << self
        # Idempotent and safe to call on every boot. Registering explicitly
        # also covers the case where the plugin file was required earlier and
        # its registration was reset in between (common in test suites).
        def configure(value = {})
          settings = normalize(value)
          validate_keys!(settings)

          FactoryBakery.register_plugin(Plugin)
          settings.each { |key, setting| Associations.public_send("#{key}=", setting) }
        end

        private

        def normalize(value)
          return {} if value == true
          return value if value.is_a?(Hash)
          return { mode: value } if Associations::MODES.include?(value)

          raise ArgumentError,
                "associations config must be a Hash, true, false or a mode symbol, got #{value.inspect}"
        end

        def validate_keys!(settings)
          unknown = settings.keys - Associations::SCOPE_KEYS
          return if unknown.empty?

          raise ArgumentError,
                "unknown associations config option #{unknown.first.inspect}; " \
                "expected one of #{Associations::SCOPE_KEYS.inspect}"
        end
      end
    end
  end
end
