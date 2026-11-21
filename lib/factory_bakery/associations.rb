# frozen_string_literal: true

require 'factory_bakery'

require_relative 'associations/configuration'
require_relative 'associations/declaration'
require_relative 'associations/declaration_rules'
require_relative 'associations/dsl'
require_relative 'associations/graph_validity'
require_relative 'associations/back_edge_detector'
require_relative 'associations/fk_parent_persistence'
require_relative 'associations/belongs_to_builder'
require_relative 'associations/reuse_resolver'
require_relative 'associations/target_builder'
require_relative 'associations/required_has_one_builder'
require_relative 'associations/natural_key_builder'
require_relative 'associations/all_auto_builder'
require_relative 'associations/plugin'
require_relative 'associations/rail_config'

# Requiring this file is the opt-in switch. Registration is idempotent per
# plugin object, so requiring it twice is harmless.
FactoryBakery.register_plugin(FactoryBakery::Associations::Plugin)
