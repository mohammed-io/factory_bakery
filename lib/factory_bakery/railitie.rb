# frozen_string_literal: true

require 'rails'

module FactoryBakery
  # Rails integration. Intentionally thin: it only decides which directory the
  # framework-agnostic loader should look at, then hands off to the core API.
  # All path globbing and file loading lives in DefinitionLoader.
  class Railtie < Rails::Railtie
    # Conventional definition locations in priority order, relative to the
    # application root. The first one that exists on disk wins.
    DEFAULT_DEFINITION_PATHS = %w[spec/factories test/factories factories].freeze

    config.factory_bakery = ActiveSupport::OrderedOptions.new

    config.after_initialize do |app|
      FactoryBakery::Railtie.install_definitions(app)
    end

    class << self
      # Resolves the configured (or conventional) definition paths and asks the
      # core to load them. Called once by the after_initialize hook on boot.
      def install_definitions(app)
        FactoryBakery.definition_paths = resolved_paths(app)
        FactoryBakery.find_definitions
      end

      private

      def resolved_paths(app)
        configured = config.factory_bakery.definition_paths
        return configured unless configured.nil?

        candidates = default_candidate_paths(app)
        existing = candidates.find { |path| File.directory?(path) }
        existing ? [existing] : candidates
      end

      def default_candidate_paths(app)
        DEFAULT_DEFINITION_PATHS.map do |relative_path|
          File.expand_path(relative_path, app.root.to_s)
        end
      end
    end
  end
end
