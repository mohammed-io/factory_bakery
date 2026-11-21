# frozen_string_literal: true

require 'rails/generators'

module FactoryBakery
  module Generators
    # Adds an initializer and creates the application's definition directory.
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path('templates', __dir__)

      def install
        paths = ActiveRecordMapper::DefinitionPaths.new(Rails.application)
        @bakery_directory = paths.bakery_directory if paths.factory_bot?
        @seed_framework = seed_framework
        template 'initializer.rb.tt', 'config/initializers/factory_bakery.rb', skip: true
        empty_directory @bakery_directory || paths.write_path
      end

      private

      # One framework slot exists for the seed, so the app's layout picks it:
      # a spec directory means RSpec, a test directory means Minitest.
      def seed_framework
        return 'rspec' if Rails.root.join('spec').directory?

        'minitest' if Rails.root.join('test').directory?
      end
    end
  end
end
