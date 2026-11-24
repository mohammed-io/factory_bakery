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

# Development-only: the opt-in Sequel mapper plugin (require
# 'factory_bakery/sequel') specs bake Sequel::Model classes on their own
# in-memory SQLite connection. Never a runtime dependency of the gemspec.
gem 'sequel'

# All three adapters are installed so DATABASE_URL can select any of them
# from any gemfile; in-memory SQLite remains the default with no env var.
gem 'pg', '~> 1.5'
gem 'mysql2', '~> 0.5'

gem 'activerecord-jdbcsqlite3-adapter', platforms: [:jruby]

gem 'sqlite3', platforms: [:ruby]

gem 'appraisal'

# Coverage for the regex generator (100% line + branch is enforced in the
# spec run; see spec/spec_helper.rb).
gem 'simplecov', '~> 1.3', require: false

# Parses the regex generator's source in its isolation guard spec (stdlib on
# Ruby >= 3.3; the gem covers Ruby 3.2).
gem 'prism'

# Development-only performance tooling for benchmark/perf/ (never in the
# gemspec): factory_bot is the comparison baseline, the rest measure and
# profile. Not required by the spec run.
group :benchmark do
  gem 'benchmark-ips', require: false
  gem 'factory_bot', require: false
  gem 'memory_profiler', require: false
  gem 'stackprof', require: false, platforms: [:ruby]
  gem 'vernier', require: false, platforms: [:ruby]
end
