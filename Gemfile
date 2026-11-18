# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in factory_bakery.gemspec
gemspec

gem 'rake'

gem 'rspec'

gem 'rubocop'

# The Railtie requires Rails at load time, so plain `bundle exec rspec` needs
# it here (rather than making the require conditional and breaking the Railtie
# specs). See the Development section of the README.
gem 'rails'

# All three adapters are installed so DATABASE_URL can select any of them
# from any gemfile; in-memory SQLite remains the default with no env var.
gem 'pg', '~> 1.5'
gem 'mysql2', '~> 0.5'

gem 'activerecord-jdbcsqlite3-adapter', platforms: [:jruby]

gem 'sqlite3', platforms: [:ruby]

gem 'appraisal'
