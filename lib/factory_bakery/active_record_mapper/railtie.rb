# frozen_string_literal: true

require_relative 'definition_paths'

module FactoryBakery
  # Wires FactoryBakery into Rails boot, generators and Rake.
  class Railtie < Rails::Railtie
    config.factory_bakery = ActiveSupport::OrderedOptions.new

    # A reload replaces model classes, so cached polymorphic candidates would
    # point at stale constants; to_prepare runs on boot and on every reload.
    config.to_prepare { FactoryBakery::ActiveRecordMapper::PolymorphicTargetDiscovery.reset! }

    config.after_initialize do |app|
      FactoryBakery::Railtie.install_associations
      fill_optional = app.config.factory_bakery.fill_optional
      FactoryBakery.fill_optional = fill_optional unless fill_optional.nil?
      FactoryBakery::Railtie.install_definitions(app)
    end

    generators do |app|
      FactoryBakery::Railtie.configure_generator(app)
    end

    rake_tasks do
      load File.expand_path('../../tasks/factory_bakery.rake', __dir__)
    end

    class << self
      def configure_generator(app)
        generators = app.config.generators
        setting = app.config.factory_bakery.generators
        framework = generators.test_framework
        return unless framework

        framework_options = generators.options[framework]
        replacement = framework_options[:fixture_replacement]
        replacement = generators.fixture_replacement if replacement.nil?
        framework_options[:fixture_replacement] = generator_replacement(setting, replacement)
      end

      # Opt-in wiring for the associations plugin. Unset or false leaves core
      # behavior untouched. When enabled, the plugin is loaded and configured
      # before definitions are loaded, since definitions may use `association`.
      # All validation and settings live in the plugin.
      def install_associations
        setting = config.factory_bakery.associations
        return if setting.nil? || setting == false

        require 'factory_bakery/associations'
        FactoryBakery::Associations::RailConfig.configure(setting)
      end

      # Resolves the configured (or conventional) definition paths and asks the
      # core to load them. Called once by the after_initialize hook on boot.
      def install_definitions(app)
        FactoryBakery.definition_paths = ActiveRecordMapper::DefinitionPaths.new(app).read_paths
        FactoryBakery.find_definitions
      end

      private

      def generator_replacement(setting, existing)
        return :factory_bakery if setting == true
        return nil if setting == false && existing == :factory_bakery
        return existing if setting == false || !existing.nil?

        :factory_bakery
      end
    end
  end
end
