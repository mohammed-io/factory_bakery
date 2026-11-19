# frozen_string_literal: true

# The default ORM mapper plugin, auto-loaded by FactoryBakery::MapperRegistry.
# It normalizes schema-backed models and validator-bearing plain objects into
# the framework-agnostic data the core consumes.
#
# This file is framework world and deliberately lives outside the
# framework-agnostic core: it requires its own ORM, registers the mapper with
# the core, and (inside a framework boot) defines the framework's integration
# glue. An app whose bundle does not include the ORM keeps a mapper-less core
# and plain targets keep working exactly as before.

begin
  require 'active_record'
rescue LoadError
  # The ORM gem is not in this bundle; this mapper stays unregistered.
end

if defined?(::ActiveRecord::Base)
  require_relative 'active_record_mapper/reflection_cache'
  require_relative 'active_record_mapper/constraint_reader'
  require_relative 'active_record_mapper/counter_cache_detector'
  require_relative 'active_record_mapper/persistence_adapter'
  require_relative 'active_record_mapper/mapper'

  FactoryBakery::MapperRegistry.register(FactoryBakery::ActiveRecordMapper::Mapper.new)
end
