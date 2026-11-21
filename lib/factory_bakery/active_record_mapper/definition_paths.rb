# frozen_string_literal: true

module FactoryBakery
  module ActiveRecordMapper
    # Keeps Rails definition loading and file generation in the same directory.
    class DefinitionPaths
      CONVENTIONAL = %w[spec/factories test/factories factories].freeze

      def initialize(app)
        @app = app
      end

      def read_paths
        configured = @app.config.factory_bakery.definition_paths
        return configured.map { |path| expand(path) } if configured.is_a?(Array)
        return expand(configured) if configured

        [expand(default_directory)]
      end

      def write_path
        Array(read_paths).first || expand(default_directory)
      end

      def factory_bot?
        return true if defined?(::FactoryBot)

        CONVENTIONAL.any? do |directory|
          Dir.glob(File.join(expand(directory), '**', '*.rb')).any? do |file|
            File.binread(file).match?(/^[ \t]*(?:::)?FactoryBot\s*\.\s*define\b/)
          end
        end
      end

      def bakery_directory
        "#{test_directory}/bakery"
      end

      private

      def default_directory
        return bakery_directory if factory_bot?

        CONVENTIONAL.find { |path| File.directory?(expand(path)) } || "#{test_directory}/factories"
      end

      def test_directory
        framework = @app.config.generators.test_framework
        return 'spec' if framework == :rspec
        return 'spec' if !framework && File.directory?(expand('spec'))

        'test'
      end

      def expand(path)
        File.expand_path(path, @app.root)
      end
    end
  end
end
