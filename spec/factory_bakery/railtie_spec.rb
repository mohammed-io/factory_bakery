# frozen_string_literal: true

require 'spec_helper'
require 'rails'
require 'set'
require 'tmpdir'
require 'fileutils'

RSpec.describe FactoryBakery::Railtie do
  around do |example|
    Dir.mktmpdir('factory_bakery-railtie-') do |directory|
      @app_root = directory
      reset_associations_state

      begin
        example.run
      ensure
        FactoryBakery.definition_paths = []
        FactoryBakery.validate = nil
        described_class.config.factory_bakery.definition_paths = nil
        described_class.config.factory_bakery.associations = nil
        reset_associations_state
        Rails.application = nil
      end
    end
  end

  # A boot that opts into associations registers the plugin process-wide. Reset
  # it so examples (and other spec files) start from core-only behavior.
  def reset_associations_state
    FactoryBakery.reset_plugins!
    FactoryBakery::Associations.reset_configuration! if defined?(FactoryBakery::Associations)
  end

  def write_definition(relative_path, source)
    path = File.join(@app_root, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
  end

  # Rails freezes some global autoload state on the first boot, so restore it
  # before booting another application in the same process.
  def reset_rails_globals
    ActiveSupport::Dependencies.autoload_paths = []
    ActiveSupport::Dependencies.autoload_once_paths = []
    ActiveSupport::Dependencies._eager_load_paths = Set.new
    Rails.application = nil
  end

  # Boots a real Rails::Application through initialize!, so the Railtie's
  # after_initialize hook runs exactly as it does in a host app.
  def boot_app(&configure)
    reset_rails_globals

    app_class = Class.new(Rails::Application) do
      config.eager_load = false
      config.secret_key_base = 'x' * 64
    end
    app_class.config.root = @app_root
    configure&.call(app_class.config)
    app_class.initialize!
    app_class.instance
  end

  def stub_target(name)
    stub_const(name, Class.new { attr_accessor :name })
  end

  it 'loads definitions from spec/factories automatically after initialize' do
    stub_target('RailtieSpecFactoriesTarget')
    write_definition(
      'spec/factories/railtie_spec_factories_target.rb',
      "FactoryBakery.define(RailtieSpecFactoriesTarget) { name { 'from spec/factories' } }\n"
    )

    boot_app

    expect(FactoryBakery.definition_paths).to eq([File.join(@app_root, 'spec/factories')])
    expect(FactoryBakery.bake(RailtieSpecFactoriesTarget).name).to eq('from spec/factories')
  end

  it 'falls back to test/factories when spec/factories does not exist' do
    stub_target('RailtieTestFactoriesTarget')
    write_definition(
      'test/factories/railtie_test_factories_target.rb',
      "FactoryBakery.define(RailtieTestFactoriesTarget) { name { 'from test/factories' } }\n"
    )

    boot_app

    expect(FactoryBakery.definition_paths).to eq([File.join(@app_root, 'test/factories')])
    expect(FactoryBakery.bake(RailtieTestFactoriesTarget).name).to eq('from test/factories')
  end

  it 'falls back to the top-level factories directory when neither conventional test directory exists' do
    stub_target('RailtieRootFactoriesTarget')
    write_definition(
      'factories/railtie_root_factories_target.rb',
      "FactoryBakery.define(RailtieRootFactoriesTarget) { name { 'from factories' } }\n"
    )

    boot_app

    expect(FactoryBakery.definition_paths).to eq([File.join(@app_root, 'factories')])
    expect(FactoryBakery.bake(RailtieRootFactoriesTarget).name).to eq('from factories')
  end

  it 'uses only the first existing conventional directory' do
    stub_target('RailtieFirstExistingTarget')
    write_definition(
      'spec/factories/railtie_first_existing_target.rb',
      "FactoryBakery.define(RailtieFirstExistingTarget) { name { 'first existing wins' } }\n"
    )
    write_definition(
      'test/factories/railtie_first_existing_target.rb',
      "FactoryBakery.define(RailtieFirstExistingTarget) { name { 'should not load' } }\n"
    )

    boot_app

    expect(FactoryBakery.definition_paths).to eq([File.join(@app_root, 'spec/factories')])
    expect(FactoryBakery.bake(RailtieFirstExistingTarget).name).to eq('first existing wins')
  end

  it 'loads definitions recursively under the selected directory via the core loader' do
    stub_target('RailtieNestedTarget')
    write_definition(
      'factories/deeply/nested/railtie_nested_target.rb',
      "FactoryBakery.define(RailtieNestedTarget) { name { 'nested railtie definition' } }\n"
    )

    boot_app

    expect(FactoryBakery.bake(RailtieNestedTarget).name).to eq('nested railtie definition')
  end

  it 'honors an array override set through config.factory_bakery.definition_paths' do
    stub_target('RailtieOverriddenTarget')
    write_definition(
      'config/factories/railtie_overridden_target.rb',
      "FactoryBakery.define(RailtieOverriddenTarget) { name { 'from override' } }\n"
    )
    write_definition(
      'spec/factories/railtie_overridden_target.rb',
      "FactoryBakery.define(RailtieOverriddenTarget) { name { 'default should not load' } }\n"
    )
    custom_path = File.join(@app_root, 'config/factories')

    boot_app do |config|
      config.factory_bakery.definition_paths = [custom_path]
    end

    expect(FactoryBakery.definition_paths).to eq([custom_path])
    expect(FactoryBakery.bake(RailtieOverriddenTarget).name).to eq('from override')
  end

  it 'honors a single-string override set through config.factory_bakery.definition_paths' do
    stub_target('RailtieStringOverrideTarget')
    write_definition(
      'custom/factories/railtie_string_override_target.rb',
      "FactoryBakery.define(RailtieStringOverrideTarget) { name { 'string override' } }\n"
    )
    custom_path = File.join(@app_root, 'custom/factories')

    boot_app do |config|
      config.factory_bakery.definition_paths = custom_path
    end

    expect(FactoryBakery.definition_paths).to eq(custom_path)
    expect(FactoryBakery.bake(RailtieStringOverrideTarget).name).to eq('string override')
  end

  it 'loads symbol-keyed definitions before their model constant exists' do
    write_definition(
      'spec/factories/railtie_lazy_target.rb',
      "FactoryBakery.define(:railtie_lazy_target) { name { 'lazy symbol' } }\n"
    )
    expect(Object.const_defined?(:RailtieLazyTarget, false)).to be(false)

    boot_app
    stub_target('RailtieLazyTarget')

    expect(FactoryBakery.bake(:railtie_lazy_target).name).to eq('lazy symbol')
  end

  it 'does not raise when no conventional directory exists' do
    expect { boot_app }.not_to raise_error
  end

  # A reload replaces model classes, so the to_prepare callback must have
  # cleared the class cache by the time boot finishes: a fact cached before
  # the boot is recomputed afterwards, for the fresh constant.
  it 'clears the class cache in the to_prepare callback run at boot' do
    target = stub_target('RailtiePrepareTarget')
    FactoryBakery::ClassCache.fetch(target, :@factory_bakery_fact) { :stale }

    boot_app

    expect(FactoryBakery::ClassCache.fetch(target, :@factory_bakery_fact) { :fresh }).to eq(:fresh)
  end

  describe 'config.factory_bakery.savepoints' do
    it 'sets FactoryBakery.savepoints? at boot' do
      boot_app do |config|
        config.factory_bakery.savepoints = true
      end

      expect(FactoryBakery.savepoints?).to be(true)
    end
  end

  describe 'config.factory_bakery.validate' do
    it 'sets FactoryBakery.validate? at boot' do
      boot_app do |config|
        config.factory_bakery.validate = false
      end

      expect(FactoryBakery.validate?).to be(false)
    end
  end

  describe 'config.factory_bakery.associations' do
    def define_optional_parent_and_child(prefix)
      parent = define_model("#{prefix}Account", name: :string)
      child = define_model("#{prefix}User", name: :string, account_id: :integer) do
        belongs_to :account, class_name: "#{prefix}Account", optional: true
      end
      [parent, child]
    end

    it 'loads and configures the plugin from a Hash before definitions load' do
      parent, child = define_optional_parent_and_child('RailtieAssocHash')
      write_definition(
        'spec/factories/railtie_assoc_hash_user.rb',
        "raise 'plugin not configured' unless FactoryBakery::Associations.mode == :all\n" \
        "FactoryBakery.define(RailtieAssocHashUser) { association :account }\n"
      )

      boot_app do |config|
        config.factory_bakery.associations = { mode: :all }
      end

      expect(FactoryBakery::Associations.mode).to eq(:all)
      expect(FactoryBakery.bake(child).account).to be_a(parent)
    end

    it 'applies every supported Hash key through the plugin setters' do
      boot_app do |config|
        config.factory_bakery.associations = {
          mode: :all, strategy: :reuse_non_unique, max_depth: 4, default_count: 3
        }
      end

      expect(FactoryBakery::Associations.mode).to eq(:all)
      expect(FactoryBakery::Associations.strategy).to eq(:reuse_non_unique)
      expect(FactoryBakery::Associations.max_depth).to eq(4)
      expect(FactoryBakery::Associations.default_count).to eq(3)
    end

    it 'loads the plugin with defaults when set to true' do
      parent, child = define_optional_parent_and_child('RailtieAssocTrue')
      FactoryBakery.define(child) { association :account }

      boot_app do |config|
        config.factory_bakery.associations = true
      end

      expect(FactoryBakery::Associations.mode).to eq(:required_only)
      expect(FactoryBakery::Associations.strategy).to eq(:fresh)
      expect(FactoryBakery.bake(child).account).to be_a(parent)
    end

    it 'loads the plugin in :none mode so nothing is built automatically' do
      _parent, child = define_optional_parent_and_child('RailtieAssocNone')

      boot_app do |config|
        config.factory_bakery.associations = { mode: :none }
      end

      expect(FactoryBakery::Associations.mode).to eq(:none)
      expect(FactoryBakery.bake(child).account).to be_nil
    end

    it 'accepts a bare mode symbol as a shorthand for { mode: value }' do
      parent, child = define_optional_parent_and_child('RailtieAssocSymbol')

      boot_app do |config|
        config.factory_bakery.associations = :all
      end

      expect(FactoryBakery::Associations.mode).to eq(:all)
      expect(FactoryBakery.bake(child).account).to be_a(parent)
    end

    it 'does not load the plugin when the config is unset' do
      child = stub_target('RailtieAssocUnsetTarget')
      FactoryBakery.define(child) { association :anything }

      boot_app

      expect { FactoryBakery.bake(child) }
        .to raise_error(FactoryBakery::Error, /requires the associations plugin/)
    end

    it 'does not load the plugin when the config is explicitly false' do
      child = stub_target('RailtieAssocFalseTarget')
      FactoryBakery.define(child) { association :anything }

      boot_app do |config|
        config.factory_bakery.associations = false
      end

      expect { FactoryBakery.bake(child) }
        .to raise_error(FactoryBakery::Error, /requires the associations plugin/)
    end

    it 'raises a clear ArgumentError at boot for an unknown config key' do
      expect do
        boot_app do |config|
          config.factory_bakery.associations = { moode: :none }
        end
      end.to raise_error(ArgumentError, /moode/)
    end

    it 'raises a clear ArgumentError at boot for an invalid config value' do
      expect do
        boot_app do |config|
          config.factory_bakery.associations = { mode: :bogus }
        end
      end.to raise_error(ArgumentError, /bogus/)
    end

    it 'coexists with a custom definition_paths override' do
      parent, child = define_optional_parent_and_child('RailtieAssocCoexist')
      write_definition(
        'config/factories/railtie_assoc_coexist_user.rb',
        "FactoryBakery.define(RailtieAssocCoexistUser) { association :account }\n"
      )
      custom_path = File.join(@app_root, 'config/factories')

      boot_app do |config|
        config.factory_bakery.definition_paths = [custom_path]
        config.factory_bakery.associations = { mode: :all }
      end

      expect(FactoryBakery.definition_paths).to eq([custom_path])
      expect(FactoryBakery.bake(child).account).to be_a(parent)
    end
  end
end
