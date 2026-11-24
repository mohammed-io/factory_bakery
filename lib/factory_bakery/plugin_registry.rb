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
        replace_plugin_list(plugins + [plugin])
        plugin
      end

      def unregister(plugin)
        return plugin unless plugins.any? { |registered| registered.equal?(plugin) }

        remaining = plugins.reject { |registered| registered.equal?(plugin) }
        @dsl_owners = owners_for(remaining)
        replace_plugin_list(remaining)
        plugin
      end

      def reset!
        @dsl_owners = {}.freeze
        replace_plugin_list([])
      end

      # A module to extend a definition scope with. Each DSL method is wrapped
      # so core knows which plugin's bucket record_plugin_declaration belongs
      # in; the wrapper then delegates to the plugin's own method via super.
      def dsl_scope_module
        snapshot.dsl_scope_module
      end

      # One immutable view of the registry: the plugin list and the DSL module
      # that belongs to exactly that list, published together with a single
      # assignment. A build captures one snapshot and consults it for every
      # registry answer, so a registration that happens mid-build can neither
      # mix a new plugin list with an old DSL module nor replay the old
      # registry over the new one; a reader sees the whole previous
      # generation or the whole new one.
      def snapshot
        published = @snapshot
        return published if published && published.plugins.equal?(plugins)

        list = plugins
        fresh = Snapshot.new(list, list.empty? ? nil : build_dsl_scope_module(list)).freeze
        PUBLISH_MUTEX.synchronize do
          # A registration that completed while this generation was being
          # built has the newer list; adopt it rather than republishing this
          # stale one over it. A stale publication can survive one read at
          # worst: the next reader compares the list identities again.
          @snapshot = fresh if @snapshot.nil? || @snapshot.plugins.equal?(list)
        end
        @snapshot || fresh
      end

      # Which plugin's DSL method is executing, so
      # `record_plugin_declaration` routes the entry into that plugin's own
      # bucket. Kept in Thread.current, whose storage belongs to the
      # executing fiber alone: Fiber[] storage is copied into fibers created
      # inside the call, and a fiber a DSL call spawned must not report the
      # plugin when it is resumed after the call has ended.
      def current
        Thread.current[CURRENT_PLUGIN_KEY]
      end

      def with_current(plugin)
        previous = current
        Thread.current[CURRENT_PLUGIN_KEY] = plugin
        yield
      ensure
        Thread.current[CURRENT_PLUGIN_KEY] = previous
      end

      def reserved_error_message(name)
        hint = RESERVED_DSL_METHODS[name.to_sym]
        return nil unless hint

        "`#{name}` requires the associations plugin: #{hint}"
      end

      private

      # Replaces the plugin list and drops the published snapshot with it, so
      # the next reader builds a generation for the new list. The old
      # generation becomes unreachable with the builders that captured it.
      def replace_plugin_list(list)
        @plugins = list.freeze
        @snapshot = nil
      end

      def dsl_owners
        @dsl_owners ||= {}.freeze
      end

      def owners_for(list)
        list.each_with_object({}) { |plugin, owners| owners.merge!(dsl_owners_for(plugin)) }.freeze
      end

      def dsl_owners_for(plugin)
        dsl = plugin.respond_to?(:dsl_module) ? plugin.dsl_module : nil
        return {} unless dsl.is_a?(Module)

        dsl.instance_methods(false).each_with_object({}) { |name, owners| owners[name] = plugin }
      end

      def build_dsl_scope_module(list)
        return nil if list.empty?

        Module.new.tap do |scope|
          list.each do |plugin|
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

    # One frozen generation of the registry: the plugin list and the DSL
    # module built from exactly that list. The registry's `plugins` list is
    # replaced wholesale on every change, so `plugins` identity decides
    # whether a published snapshot is still current.
    Snapshot = Struct.new(:plugins, :dsl_scope_module)

    # Publishing one snapshot generation is the registry's only shared
    # mutation, and it happens under this mutex; the DSL module inside is
    # built outside it (it may run plugin code). Never held while user code
    # runs.
    PUBLISH_MUTEX = Mutex.new
  end
end
