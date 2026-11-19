# frozen_string_literal: true

module FactoryBakery
  # Loads definition files from the configured directories. No framework or
  # test-framework dependency: a host application (or its integration glue)
  # only needs to set definition_paths.
  class DefinitionLoader
    def self.call(paths)
      Array(paths).each do |path|
        # Kernel#load re-evaluates files on every call (unlike require), which
        # makes find_definitions reload-friendly. File errors propagate and
        # files from earlier paths are already loaded when one fails.
        ruby_files_in(path).each { |file| Kernel.load(File.expand_path(file)) }
      end
    end

    def self.ruby_files_in(path)
      return [] unless File.directory?(path)

      Dir.glob(File.join(path, '**', '*.rb')).sort
    end
    private_class_method :ruby_files_in
  end
end
