# frozen_string_literal: true

require 'ffaker'
require 'date'
require 'time'
require_relative 'factory_bakery/version'
require_relative 'factory_bakery/plugin_registry'
require_relative 'factory_bakery/constraint_set'
require_relative 'factory_bakery/fill_optional'
require_relative 'factory_bakery/required_attribute'
require_relative 'factory_bakery/fallback_builder'
require_relative 'factory_bakery/mapper_registry'
require_relative 'factory_bakery/bakery_builder'
require_relative 'factory_bakery/build_context'
require_relative 'factory_bakery/persistence_verifier'
require_relative 'factory_bakery/read_only_guard'
require_relative 'factory_bakery/regex_generation'
require_relative 'factory_bakery/definition_loader'
require_relative 'factory_bakery/methods'

# Attribute fillers
require_relative 'factory_bakery/attribute_fillers/value_resolution'
require_relative 'factory_bakery/attribute_fillers/plausible_strings'
require_relative 'factory_bakery/attribute_fillers/numeric_constraint_hygiene'
require_relative 'factory_bakery/attribute_fillers/bake_time_values'
require_relative 'factory_bakery/attribute_fillers/noop_filler'
require_relative 'factory_bakery/attribute_fillers/guarded_writer_filler'
require_relative 'factory_bakery/attribute_fillers/string_filler'
require_relative 'factory_bakery/attribute_fillers/integer_filler'
require_relative 'factory_bakery/attribute_fillers/float_filler'
require_relative 'factory_bakery/attribute_fillers/boolean_filler'
require_relative 'factory_bakery/attribute_fillers/temporal_arithmetic'
require_relative 'factory_bakery/attribute_fillers/date_filler'
require_relative 'factory_bakery/attribute_fillers/datetime_filler'
require_relative 'factory_bakery/attribute_fillers/enum_filler'
require_relative 'factory_bakery/attribute_fillers/json_filler'
require_relative 'factory_bakery/attribute_fillers/array_filler'
require_relative 'factory_bakery/attribute_fillers/acceptance_filler'
require_relative 'factory_bakery/attribute_fillers/confirmation_filler'
require_relative 'factory_bakery/attribute_fillers/filler_selector'
require_relative 'factory_bakery/uniqueness_enforcer'

module FactoryBakery
  class Error < StandardError; end
  class NestingTooDeepError < Error; end
  class CyclicAssociationError < Error; end
  class IncompletePersistenceError < Error; end
  class ReadOnlyTargetError < Error; end

  class << self
    attr_writer :definition_paths, :max_bake_depth

    # Process-wide configuration block, mirroring the other global settings.
    def configure
      yield self
    end

    # By default a bake fills only what a valid record needs. Set this to true
    # to restore filling every column, or pass `fill_optional:` to one bake.
    def fill_optional
      FillOptional.global
    end

    # Validated and normalized like the per-call option, so `%i[bio]` and
    # `%w[bio]` behave the same and a typo such as `'true'` raises.
    def fill_optional=(value)
      FillOptional.global = value.nil? ? false : normalize_fill_optional(value)
    end

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

    def bake(target, *traits, fill_optional: nil, **overrides)
      mode = normalize_fill_optional(fill_optional)
      FillOptional.with(mode) do
        model_klass, definition = BakeryBuilder.resolve(target)
        BuildContext.push(model_klass) do
          build_with_fallback(model_klass, definition, overrides, traits, mode)
        end
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
    def bake!(target, *traits, fill_optional: nil, **overrides)
      mode = normalize_fill_optional(fill_optional)
      # FK-column-validated edges insert their parent while the graph is being
      # built, so the flag must cover graph building too, not just the save.
      BuildContext.with_persistence do
        FillOptional.with(mode) do
          model_klass, definition = BakeryBuilder.resolve(target)
          adapter = MapperRegistry.persistence_adapter(model_klass)

          return bake_untransactional(target, adapter, overrides, traits, mode) unless adapter.transactional?

          object = nil
          adapter.transaction(model_klass) do
            object = BuildContext.push(model_klass) do
              record = build_with_fallback(model_klass, definition, overrides, traits, mode)
              # Check before any save: a read-only target cannot be persisted,
              # and a read-only parent generated anywhere in the graph fails
              # the whole bake! inside this savepoint.
              ensure_writable!(record, adapter)
              adapter.save!(record)
              verify_persistence!(record, adapter)
              record
            end
          end
          object
        end
      end
    end

    private

    def normalize_fill_optional(value)
      return FillOptional.current if value.nil?
      return value if [true, false].include?(value)
      return value.map(&:to_s) if value.is_a?(Array)

      raise ArgumentError, "fill_optional must be true, false, or an array of attribute names, got #{value.inspect}"
    end

    def build_with_fallback(model_klass, definition, overrides, traits, mode)
      FallbackBuilder.new(mode).build(model_klass, definition, overrides, traits)
    end

    def verify_persistence!(root, adapter)
      entries = BuildContext.records_under(BuildContext.current.path)
      PersistenceVerifier.new(root, entries, adapter).call
    end

    def bake_untransactional(target, adapter, overrides, traits, mode)
      object = bake(target, *traits, fill_optional: mode, **overrides)
      ensure_writable!(object, adapter)
      adapter.save!(object)
      object
    end

    # Read-only targets are fine for `bake` but cannot be written. The guard
    # runs after graph building and before the root save, inside the savepoint
    # that rolls back any parent the graph inserted earlier.
    def ensure_writable!(root, adapter)
      entries = BuildContext.records_under(BuildContext.current.path)
      ReadOnlyGuard.new(root, adapter, entries).call
    end
  end
end

# Auto-register the built-in mapper plugins. Each plugin requires its own
# framework and registers itself only when that framework is available; the
# framework-agnostic core never references a framework constant.
FactoryBakery::MapperRegistry.load_default_mappers
