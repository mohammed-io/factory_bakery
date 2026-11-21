# frozen_string_literal: true

require_relative '../definition/definition_generator'

module FactoryBakery
  module Generators
    # Adapts the standalone generator to Rails' fixture replacement hook.
    class ModelGenerator < DefinitionGenerator
      source_root DefinitionGenerator.source_root

      class_option :factory_bakery, type: :boolean, default: true

      def write_definition
        super if options[:factory_bakery]
      end
    end
  end
end
