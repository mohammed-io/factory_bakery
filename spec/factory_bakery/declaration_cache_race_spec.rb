# frozen_string_literal: true

require 'spec_helper'
require 'rails'
require 'set'
require 'tmpdir'

# The declaration cache hangs off a definition block and is shared by every
# bake in the process, so registry changes and reloads that interleave with a
# bake must not make one build read another build's registry generation.
# Observable contract: a recording that spans a plugin registration stays in
# its own scope, a builder answers every registry question from the snapshot
# it was created with, concurrent first use publishes one cache, and
# reset_cache! (and the Rails reload hook) make recorded layers be recorded
# again.
RSpec.describe 'declaration cache under registration and reload races' do
  before { FactoryBakery.reset_plugins! }
  after { FactoryBakery.reset_plugins! }

  # A plugin whose DSL method `value` records a fixed reusable entry and
  # whose after_instantiate hook copies the entry onto the record, so a bake
  # answers "which declarations did this build see".
  def entry_plugin
    dsl = Module.new do
      def value(*)
        record_plugin_declaration(:plugin_entry, reusable: true)
      end
    end
    plugin = Object.new
    plugin.define_singleton_method(:dsl_module) { dsl }
    plugin.define_singleton_method(:after_instantiate) do |record, entries, _context|
      record.value = entries.first if entries.any?
    end
    plugin
  end

  def holder_class
    Class.new do
      attr_accessor :value
    end
  end

  describe 'a recording that spans a plugin registration' do
    it 'does not leak the old scope into the registered scope' do
      record_class = holder_class
      started = Queue.new
      release = Queue.new
      first_recording = true
      FactoryBakery.define(record_class) do
        if first_recording
          started << :recording
          release.pop
        end
        value { :attribute }
      end

      # Records the block under no plugins, suspended before its `value` call.
      slow_recording = Thread.new { FactoryBakery.bake(record_class) }
      expect(started.pop).to eq(:recording)

      first_recording = false
      FactoryBakery.register_plugin(entry_plugin)
      expect(FactoryBakery.bake(record_class).value).to eq(:plugin_entry)

      release << :go
      slow_recording.join
      # The suspended recording finishes into the no-plugin scope it started
      # under; the registered scope keeps serving what it recorded.
      expect(FactoryBakery.bake(record_class).value).to eq(:plugin_entry)
    end
  end

  describe 'a builder that outlives a registry change' do
    it 'answers every registry question from the snapshot it was created with' do
      FactoryBakery.register_plugin(entry_plugin)
      record_class = holder_class
      FactoryBakery.define(record_class) { value { :attribute } }
      builder = FactoryBakery::BakeryBuilder.for_current_plugins.new(
        record_class, FactoryBakery::BakeryBuilder.definitions[record_class].builder_proc
      )

      FactoryBakery.reset_plugins!

      # The stale builder records and replays coherently under its own
      # snapshot: the entry lands in the plugin's bucket and the hook runs.
      expect(builder.build.value).to eq(:plugin_entry)

      # A bake under the emptied registry reads the block's current meaning
      # (a plain attribute), not the stale builder's cached result.
      expect(FactoryBakery.bake(record_class).value).to eq(:attribute)

      # Re-registering records under the plugin scope again.
      FactoryBakery.register_plugin(entry_plugin)
      expect(FactoryBakery.bake(record_class).value).to eq(:plugin_entry)
    end
  end

  describe 'concurrent first use' do
    it 'publishes one cache per definition block' do
      holder = proc {}
      go = Queue.new
      caches = Array.new(2) do
        Thread.new do
          go.pop
          FactoryBakery::DeclarationCache.for(holder)
        end
      end
      go << :go << :go
      caches.each(&:join)

      published = caches.map(&:value)
      expect(published).to all(be_a(FactoryBakery::DeclarationCache))
      expect(published.map(&:object_id).uniq.size).to eq(1)
    end

    it 'caches the definition after competing first recordings' do
      record_class = holder_class
      recordings = 0
      FactoryBakery.define(record_class) do
        recordings += 1
        value { :attribute }
      end

      go = Queue.new
      bakes = Array.new(2) do
        Thread.new do
          go.pop
          FactoryBakery.bake(record_class)
        end
      end
      go << :go << :go
      bakes.each(&:join)

      expect(bakes.map { _1.value.value }).to all(eq(:attribute))
      recordings_after_race = recordings
      FactoryBakery.bake(record_class)
      expect(recordings).to eq(recordings_after_race)
    end
  end

  describe 'reset_cache!' do
    it 'makes recorded declaration layers be recorded again' do
      record_class = holder_class
      recordings = 0
      FactoryBakery.define(record_class) do
        recordings += 1
        value { :attribute }
      end

      FactoryBakery.bake(record_class)
      expect(recordings).to eq(1)

      FactoryBakery.reset_cache!
      FactoryBakery.bake(record_class)
      expect(recordings).to eq(2)

      FactoryBakery.bake(record_class)
      expect(recordings).to eq(2)
    end
  end

  describe 'the Rails reload hook' do
    # The Railtie's to_prepare callback runs at boot (and on every reload in a
    # host app), so a minimal application boot exercises it exactly as a
    # reload does.
    around do |example|
      ActiveSupport::Dependencies.autoload_paths = []
      ActiveSupport::Dependencies.autoload_once_paths = []
      ActiveSupport::Dependencies._eager_load_paths = Set.new
      Rails.application = nil
      definition_paths = FactoryBakery.definition_paths.dup
      begin
        example.run
      ensure
        Rails.application = nil
        # The Railtie sets the process-wide definition paths while booting.
        FactoryBakery.definition_paths.replace(definition_paths)
      end
    end

    def boot_app(root)
      app_class = Class.new(Rails::Application) do
        config.eager_load = false
        config.secret_key_base = 'x' * 64
      end
      app_class.config.root = root
      app_class.initialize!
      app_class.instance
    end

    it 'invalidates recorded declaration layers at boot' do
      record_class = holder_class
      recordings = 0
      FactoryBakery.define(record_class) do
        recordings += 1
        value { :attribute }
      end
      FactoryBakery.bake(record_class)
      expect(recordings).to eq(1)

      Dir.mktmpdir('factory_bakery-reload-root-') { |root| boot_app(root) }

      FactoryBakery.bake(record_class)
      expect(recordings).to eq(2)
    end
  end
end
