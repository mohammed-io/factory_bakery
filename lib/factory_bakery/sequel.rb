# frozen_string_literal: true

# The opt-in Sequel mapper plugin. Requiring this file is the opt-in switch:
# it loads its own ORM (the sequel gem), registers a mapper with the
# framework-agnostic core, and nothing else changes. The require is
# idempotent, so requiring it twice is harmless.
#
# This file is framework world and deliberately lives outside the
# framework-agnostic core (see the architecture guard spec): every read of
# Sequel happens here or in the files under factory_bakery/sequel/. An
# application whose bundle does not include the sequel gem keeps a
# mapper-less-for-Sequel core, and the require below raises a helpful error
# instead of a raw LoadError.
#
# What maps, what does not:
#   * db_schema columns (type, limits, nullability, defaults) feed the same
#     generators the default mapper feeds, through type translation in
#     FactoryBakery::Sequel::ConstraintReader.
#   * STORED validations map into the constraint set. Sequel stores
#     validations as declarative, reflective data only under the
#     validation_class_methods plugin (`Model.validation_reflections`). The
#     validation_helpers plugin runs its checks imperatively inside
#     `Model#validate`; those calls are code, not data, so heuristics cannot
#     see them and models relying on them fall back to db_schema-driven
#     generation. That difference is documented here rather than faked.
#   * Unique indexes on the dataset schema and stored uniqueness
#     declarations both feed the uniqueness flag; the check queries the
#     model's own dataset, excluding the record itself.
#   * many_to_one associations are READ from the reflections for guard
#     columns and alias groups, but never auto-built: guarded foreign keys
#     stay nil, mirroring the guard-rail philosophy. has_one/has_many
#     orchestration stays out of scope (the opt-in associations plugin is a
#     primary-framework feature; this mapper answers `nil` association
#     introspection so the plugin raises its clear error rather than
#     guessing).
#   * Transactions: Sequel's `save` raises on validation or hook failure by
#     default (`raise_on_save_failure`), so the persistence adapter maps
#     save! to `save` and wraps bakes in `db.transaction(savepoint: true)`.

require 'factory_bakery'

begin
  require 'sequel'
rescue LoadError
  raise FactoryBakery::Error, <<~ERROR
    factory_bakery/sequel requires the sequel gem, but it is not available.

    Sequel support is opt-in and stays an optional dependency: the
    factory_bakery gemspec does not require sequel. Add the gem to your
    application's Gemfile:

      gem 'sequel'

    Then run `bundle install` and require 'factory_bakery/sequel' again.
  ERROR
end

require_relative 'sequel/constraint_reader'
require_relative 'sequel/mapper'
require_relative 'sequel/persistence_adapter'

FactoryBakery::MapperRegistry.register(FactoryBakery::Sequel::Mapper.new)
