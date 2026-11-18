# frozen_string_literal: true

require 'ffaker'
require_relative 'factory_bakery/version'
require_relative 'factory_bakery/railitie'
require_relative 'factory_bakery/plugin_registry'
require_relative 'factory_bakery/bakery_builder'
require_relative 'factory_bakery/build_context'
require_relative 'factory_bakery/counter_cache_detector'
require_relative 'factory_bakery/persistence_verifier'
require_relative 'factory_bakery/definition_loader'
require_relative 'factory_bakery/methods'

# Attribute fillers
require_relative 'factory_bakery/attribute_fillers/common_validators'
require_relative 'factory_bakery/attribute_fillers/noop_filler'
require_relative 'factory_bakery/attribute_fillers/string_filler'
require_relative 'factory_bakery/attribute_fillers/integer_filler'
require_relative 'factory_bakery/attribute_fillers/float_filler'
require_relative 'factory_bakery/attribute_fillers/boolean_filler'
require_relative 'factory_bakery/attribute_fillers/date_filler'
require_relative 'factory_bakery/attribute_fillers/datetime_filler'
require_relative 'factory_bakery/attribute_fillers/enum_filler'
require_relative 'factory_bakery/attribute_fillers/acceptance_filler'
require_relative 'factory_bakery/attribute_fillers/confirmation_filler'
require_relative 'factory_bakery/attribute_fillers/filler_selector'

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
    # disturbing the caller's transaction.
    def bake!(target, *traits, **overrides)
      model_klass, definition = BakeryBuilder.resolve(target)

      unless model_klass.respond_to?(:transaction)
        object = bake(target, *traits, **overrides)
        object.save! if object.respond_to?(:save!)
        return object
      end

      object = nil
      model_klass.transaction(requires_new: true) do
        object = BuildContext.push(model_klass) do
          record = build_object(model_klass, definition, overrides, traits)
          record.save! if record.respond_to?(:save!)
          verify_persistence!(record)
          record
        end
      end
      object
    end

    private

    def build_object(model_klass, definition, overrides, traits)
      object = BakeryBuilder.new(model_klass, definition).build(overrides: overrides, traits: traits)
      BuildContext.record_generated(object)
      object
    end

    def verify_persistence!(root)
      entries = BuildContext.records_under(BuildContext.current.path)
      PersistenceVerifier.new(root, entries).call
    end
  end
end
