# frozen_string_literal: true

module FactoryBakery
  # Holds the plugins registered through FactoryBakery.register_plugin.
  #
  # Plugins are invoked in registration order. Registration is idempotent per
  # plugin object, and two plugins may not define the same DSL method name.
  # The registry also recognizes DSL names that belong to an unloaded plugin so
  # core can raise a helpful error instead of silently recording them.
  class PluginRegistry
    CURRENT_PLUGIN_KEY = :factory_bakery_current_plugin

    RESERVED_DSL_METHODS = {
      association: "require 'factory_bakery/associations'"
    }.freeze

    class << self
      def plugins
        @plugins ||= [].freeze
      end

      def register(plugin)
        return plugin if plugins.any? { |registered| registered.equal?(plugin) }

        owners = dsl_owners_for(plugin)
        duplicate = owners.keys.find { |name| dsl_owners.key?(name) }
        if duplicate
          raise FactoryBakery::Error, "DSL method #{duplicate.inspect} is already provided by another plugin"
        end

        @dsl_owners = dsl_owners.merge(owners).freeze
        @plugins = (plugins + [plugin]).freeze
        @dsl_scope_module = nil
        plugin
      end

      def unregister(plugin)
        return plugin unless plugins.any? { |registered| registered.equal?(plugin) }

        @plugins = plugins.reject { |registered| registered.equal?(plugin) }.freeze
        rebuild!
        plugin
      end

      def reset!
        @plugins = [].freeze
        rebuild!
      end

      # A module to extend a definition scope with. Each DSL method is wrapped
      # so core knows which plugin's bucket record_plugin_declaration belongs
      # in; the wrapper then delegates to the plugin's own method via super.
      def dsl_scope_module
        @dsl_scope_module ||= build_dsl_scope_module
      end

      def current
        Fiber[CURRENT_PLUGIN_KEY]
      end

      def with_current(plugin)
        previous = current
        Fiber[CURRENT_PLUGIN_KEY] = plugin
        yield
      ensure
        Fiber[CURRENT_PLUGIN_KEY] = previous
      end

      def reserved_error_message(name)
        hint = RESERVED_DSL_METHODS[name.to_sym]
        return nil unless hint

        "`#{name}` requires the associations plugin: #{hint}"
      end

      private

      def dsl_owners
        @dsl_owners ||= {}.freeze
      end

      def dsl_owners_for(plugin)
        dsl = plugin.respond_to?(:dsl_module) ? plugin.dsl_module : nil
        return {} unless dsl.is_a?(Module)

        dsl.instance_methods(false).each_with_object({}) { |name, owners| owners[name] = plugin }
      end

      def rebuild!
        @dsl_owners = {}.freeze
        @dsl_scope_module = nil
        plugins.each do |plugin|
          @dsl_owners = dsl_owners.merge(dsl_owners_for(plugin)).freeze
        end
      end

      def build_dsl_scope_module
        return nil if plugins.empty?

        Module.new.tap do |scope|
          plugins.each do |plugin|
            dsl = plugin.respond_to?(:dsl_module) ? plugin.dsl_module : nil
            next unless dsl.is_a?(Module)

            scope.include(dsl)
            dsl.instance_methods(false).each do |name|
              owner = plugin
              scope.define_method(name) do |*args, **kwargs, &block|
                FactoryBakery::PluginRegistry.with_current(owner) do
                  super(*args, **kwargs, &block)
                end
              end
            end
          end
        end
      end
    end
  end
end
