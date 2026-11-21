# frozen_string_literal: true

require 'rails/generators'
require 'rails/generators/named_base'

module FactoryBakery
  module Generators
    # Writes one class-keyed definition, optionally with commented overrides.
    class DefinitionGenerator < Rails::Generators::NamedBase
      source_root File.expand_path('templates', __dir__)

      argument :attributes, type: :array, default: [], banner: 'field:type field:type'

      no_commands do
        attr_writer :diagnostic
      end

      def write_definition
        paths = ActiveRecordMapper::DefinitionPaths.new(Rails.application)
        path = File.join(paths.write_path, "#{class_name.underscore}.rb")
        template 'definition.rb.tt', path, skip: true
      end

      private

      def attribute_comments
        diagnostics = @diagnostic.to_s.lines(chomp: true).map { |line| "# #{line}" }
        diagnostics + attributes.map do |attribute|
          "# #{attribute.name} { #{example_value(attribute)} }"
        end
      end

      def example_value(attribute)
        return attribute.default.inspect unless attribute.reference?

        target = attribute.polymorphic? ? 'SomeModel' : attribute.name.camelize
        "FactoryBakery.bake(#{target})"
      end
    end
  end
end
