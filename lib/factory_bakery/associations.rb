# frozen_string_literal: true

require 'factory_bakery'
require 'factory_bakery/active_record_mapper/reflection_cache'

require_relative 'associations/configuration'
require_relative 'associations/declaration'
require_relative 'associations/dsl'
require_relative 'associations/back_edge_detector'
require_relative 'associations/belongs_to_builder'
require_relative 'associations/reuse_resolver'
require_relative 'associations/target_builder'
require_relative 'associations/all_auto_builder'
require_relative 'associations/plugin'
require_relative 'associations/rail_config'

module FactoryBakery
  module Associations
    # This plugin still introspects association reflections directly; moving
    # it onto the mapper's association-introspection contract is a separate
    # phase. It shares the mapper's per-class reflection cache under a local
    # alias so its call sites stay unchanged.
    ReflectionCache = ActiveRecordMapper::ReflectionCache
  end
end

# Requiring this file is the opt-in switch. Registration is idempotent per
# plugin object, so requiring it twice is harmless.
FactoryBakery.register_plugin(FactoryBakery::Associations::Plugin)
