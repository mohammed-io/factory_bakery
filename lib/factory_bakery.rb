# frozen_string_literal: true

require 'ffaker'
require 'date'
require 'time'
require_relative 'factory_bakery/version'
require_relative 'factory_bakery/plugin_registry'
require_relative 'factory_bakery/constraint_set'
require_relative 'factory_bakery/mapper_registry'
require_relative 'factory_bakery/bakery_builder'
require_relative 'factory_bakery/build_context'
require_relative 'factory_bakery/persistence_verifier'
require_relative 'factory_bakery/definition_loader'
require_relative 'factory_bakery/methods'

# Attribute fillers
require_relative 'factory_bakery/attribute_fillers/value_resolution'
require_relative 'factory_bakery/attribute_fillers/numeric_constraint_hygiene'
require_relative 'factory_bakery/attribute_fillers/bake_time_values'
require_relative 'factory_bakery/attribute_fillers/noop_filler'
require_relative 'factory_bakery/attribute_fillers/string_filler'
require_relative 'factory_bakery/attribute_fillers/integer_filler'
require_relative 'factory_bakery/attribute_fillers/float_filler'
require_relative 'factory_bakery/attribute_fillers/boolean_filler'
require_relative 'factory_bakery/attribute_fillers/temporal_arithmetic'
require_relative 'factory_bakery/attribute_fillers/date_filler'
require_relative 'factory_bakery/attribute_fillers/datetime_filler'
require_relative 'factory_bakery/attribute_fillers/enum_filler'
require_relative 'factory_bakery/attribute_fillers/json_filler'
require_relative 'factory_bakery/attribute_fillers/acceptance_filler'
require_relative 'factory_bakery/attribute_fillers/confirmation_filler'
require_relative 'factory_bakery/attribute_fillers/filler_selector'
require_relative 'factory_bakery/uniqueness_enforcer'

module FactoryBakery
  class Error < StandardError; end
  class NestingTooDeepError < Error; end
  class CyclicAssociationError < Error; end
  class IncompletePersistenceError < Error; end

  class << self
    attr_writer :definition_paths, :max_bake_depth

    # No paths are configured until the host app (or the Railtie) sets them.
    def definition_paths
      @definition_paths ||= []
    end

    # Maximum number of nested bake calls allowed within one build context.
    def max_bake_depth
      @max_bake_depth ||= 10
    end

    def find_definitions
      DefinitionLoader.call(definition_paths)
    end

    # Registers a plugin implementing any subset of dsl_module,
    # heuristic_values and after_instantiate. Registration is idempotent per
    # plugin object and invocation follows registration order.
    def register_plugin(plugin)
      PluginRegistry.register(plugin)
    end

    def unregister_plugin(plugin)
      PluginRegistry.unregister(plugin)
    end

    # Test support: clears all plugins so examples stay isolated.
    def reset_plugins!
      PluginRegistry.reset!
    end

    def define(target, klass: nil, &block)
      BakeryBuilder.register(target, klass: klass, &block)
    end

    def bake(target, *traits, **overrides)
      model_klass, definition = BakeryBuilder.resolve(target)
      BuildContext.push(model_klass) do
        build_object(model_klass, definition, overrides, traits)
      end
    end

    # `bake!` has a persistence contract: graph building (including nested
    # `bake!` calls from declaration blocks), the root `save!` and the
    # verify-and-raise step all run inside one transaction opened with
    # `requires_new`. That is a savepoint when the caller already has a
    # transaction, so a failure rolls back every row this bake wrote without
    # disturbing the caller's transaction. The transaction, save and
    # persistence check are performed through the mapper's persistence adapter;
    # a target no mapper claims keeps plain build-and-save semantics.
    def bake!(target, *traits, **overrides)
      model_klass, definition = BakeryBuilder.resolve(target)
      adapter = MapperRegistry.persistence_adapter(model_klass)

      unless adapter.transactional?
        object = bake(target, *traits, **overrides)
        adapter.save!(object)
        return object
      end

      object = nil
      adapter.transaction(model_klass) do
        object = BuildContext.push(model_klass) do
          record = build_object(model_klass, definition, overrides, traits)
          adapter.save!(record)
          verify_persistence!(record, adapter)
          record
        end
      end
      object
    end

    private

    def build_object(model_klass, definition, overrides, traits)
      builder = BakeryBuilder.new(model_klass, definition)
      object = builder.build(overrides: overrides, traits: traits)
      UniquenessEnforcer.new(object, builder.heuristic_attribute_names).call
      BuildContext.record_generated(object)
      object
    end

    def verify_persistence!(root, adapter)
      entries = BuildContext.records_under(BuildContext.current.path)
      PersistenceVerifier.new(root, entries, adapter).call
    end
  end
end

# Auto-register the built-in mapper plugins. Each plugin requires its own
# framework and registers itself only when that framework is available; the
# framework-agnostic core never references a framework constant.
FactoryBakery::MapperRegistry.load_default_mappers
