# frozen_string_literal: true

require 'uri'
require 'active_record'

# Single seam for the Rails x database test matrix.
#
# With no DATABASE_URL the suite uses in-memory SQLite (with foreign-key
# enforcement turned on), so a plain `bundle exec rspec` runs with no skips.
# Setting DATABASE_URL selects the adapter for the whole suite; the same
# specs, macros and tables then run against PostgreSQL or MySQL.
module DatabaseSupport
  class << self
    def url
      value = ENV['DATABASE_URL']
      value unless value.nil? || value.strip.empty?
    end

    def adapter
      return 'sqlite3' unless url

      case URI.parse(url).scheme.to_s.downcase
      when 'postgres', 'postgresql' then 'postgresql'
      when 'mysql', 'mysql2' then 'mysql2'
      when 'sqlite', 'sqlite3' then 'sqlite3'
      else URI.parse(url).scheme.to_s.downcase
      end
    end

    def sqlite?
      adapter == 'sqlite3'
    end

    def postgresql?
      adapter == 'postgresql'
    end

    def mysql?
      adapter == 'mysql2'
    end

    # Re-establishing a pool per example group is what gives each group a
    # fresh in-memory SQLite database. Server-backed adapters keep one pool
    # for the whole run; each example already drops the tables it creates.
    def establish_connection!
      return if @established && !sqlite?

      ActiveRecord::Base.establish_connection(url || { adapter: 'sqlite3', database: ':memory:' })
      @established = true
      enable_foreign_keys!
    end

    # SQLite needs an explicit pragma; PostgreSQL and MySQL enforce FKs by
    # default, so this is intentionally a no-op there.
    def enable_foreign_keys!
      return unless sqlite?

      ActiveRecord::Base.connection.execute('PRAGMA foreign_keys = ON')
    end

    # `jsonb` is PostgreSQL-specific. Keep using it there, and map it to
    # `json` elsewhere so the existing filler specs run on every adapter.
    def column_type(type)
      return type unless type == :jsonb

      postgresql? ? :jsonb : :json
    end

    def json_type
      postgresql? ? :jsonb : :json
    end

    # A native array column only exists on PostgreSQL. Elsewhere a JSON
    # column is the portable equivalent used by the constraint specs.
    def add_array_column(table, name)
      postgresql? ? table.string(name, array: true) : table.json(name)
    end
  end
end
