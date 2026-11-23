# frozen_string_literal: true

require 'spec_helper'

# Observable behavior of the A8 plugin seam: a spec-only plugin registered
# through FactoryBakery.register_plugin, exercised through define/bake.
RSpec.describe 'FactoryBakery plugin registry' do
  before { FactoryBakery.reset_plugins! }
  after { FactoryBakery.reset_plugins! }

  # Builds a plugin implementing only the hooks that are passed in. This keeps
  # every example honest about which hooks core has to look for.
  def plugin_with(dsl: nil, heuristics: nil, after: nil)
    plugin = Module.new
    plugin.define_singleton_method(:dsl_module) { dsl } if dsl
    plugin.define_singleton_method(:heuristic_values, &heuristics) if heuristics
    plugin.define_singleton_method(:after_instantiate, &after) if after
    plugin
  end

  # A DSL method that records the name it is given in its own per-plugin bucket.
  def recording_dsl(method_name)
    Module.new do
      define_method(method_name) do |value|
        record_plugin_declaration(value)
      end
    end
  end

  def uppercasing_after
    lambda do |object, declarations, _context|
      declarations.each do |name|
        object.public_send("#{name}=", object.public_send(name).to_s.upcase)
      end
    end
  end

  describe 'the reserved association name' do
    it 'raises a helpful error when association is used with no plugin loaded' do
      model = define_model('ReservedNoPluginUser', name: :string)
      FactoryBakery.define(model) { association :author }

      expect { FactoryBakery.bake(model) }.to raise_error(
        FactoryBakery::Error,
        "`association` requires the associations plugin: require 'factory_bakery/associations'"
      )
    end

    it 'stops raising once a plugin provides the association DSL method' do
      model = define_model('ReservedWithPluginUser', name: :string)
      FactoryBakery.register_plugin(plugin_with(dsl: recording_dsl(:association)))
      FactoryBakery.define(model) do
        name { 'ann' }
        association :author
      end

      expect { FactoryBakery.bake(model) }.not_to raise_error
    end
  end

  describe 'the dsl_module hook' do
    it 'makes DSL methods available in both define blocks and traits' do
      model = define_model('DslHookUser', name: :string, city: :string)
      FactoryBakery.register_plugin(plugin_with(dsl: recording_dsl(:shout), after: uppercasing_after))

      FactoryBakery.define(model) do
        name { 'ann' }
        shout :name
        trait :from_cairo do
          city { 'cairo' }
          shout :city
        end
      end

      record = FactoryBakery.bake(model, :from_cairo)

      expect([record.name, record.city]).to eq(%w[ANN CAIRO])
    end

    it 'raises at registration when a second plugin defines the same DSL method name' do
      FactoryBakery.register_plugin(plugin_with(dsl: recording_dsl(:shout)))
      other = plugin_with(dsl: recording_dsl(:shout))

      expect { FactoryBakery.register_plugin(other) }
        .to raise_error(FactoryBakery::Error, /shout/)
    end

    it 'ignores hooks the plugin does not implement' do
      model = define_model('DslOnlyUser', name: :string)
      FactoryBakery.register_plugin(plugin_with(dsl: recording_dsl(:shout)))
      FactoryBakery.define(model) do
        name { 'ann' }
        shout :name
      end

      expect(FactoryBakery.bake(model).name).to eq('ann')
    end
  end

  describe 'the heuristic_values hook' do
    it 'contributes values that declarations, traits and call-site overrides beat' do
      model = define_model('HeuristicHookUser', name: :string, nickname: :string)
      plugin = plugin_with(
        dsl: recording_dsl(:shout),
        heuristics: lambda do |_klass, _context, taken|
          taken.include?('nickname') ? {} : { 'nickname' => 'plugin' }
        end,
        after: uppercasing_after
      )
      FactoryBakery.register_plugin(plugin)
      FactoryBakery.define(model) do
        name { 'ann' }
        shout :name
        trait :with_trait_nickname do
          nickname { 'from-trait' }
        end
      end

      expect(FactoryBakery.bake(model).nickname).to eq('plugin')
      expect(FactoryBakery.bake(model, :with_trait_nickname).nickname).to eq('from-trait')
      expect(FactoryBakery.bake(model, nickname: 'from-call-site').nickname).to eq('from-call-site')
    end

    it 'passes taken names with alias-group members expanded' do
      account_model = define_model('TakenGroupAccount', name: :string)
      model = define_model('TakenGroupUser', name: :string, account_id: :integer) do
        belongs_to :account, class_name: 'TakenGroupAccount', optional: true
      end
      captured = nil
      plugin = plugin_with(
        heuristics: lambda do |_klass, _context, taken|
          captured = taken
          {}
        end
      )
      FactoryBakery.register_plugin(plugin)
      FactoryBakery.define(model) { account { FactoryBakery.bake(account_model) } }

      FactoryBakery.bake(model, account_id: 7)

      expect(captured).to include('account', 'account_id')
    end

    it 'does not let a same-layer nil FK clobber a plugin-supplied association object' do
      account_model = define_model('ClobberPluginAccount', name: :string)
      model = define_model('ClobberPluginUser', account_id: :integer) do
        belongs_to :account, class_name: 'ClobberPluginAccount', optional: true
      end
      parent = account_model.create!(name: 'parent')
      FactoryBakery.register_plugin(
        plugin_with(heuristics: ->(_klass, _context, _taken) { { 'account_id' => nil, 'account' => parent } })
      )

      record = FactoryBakery.bake(model)

      expect(record.account).to eq(parent)
      expect(record.account_id).to eq(parent.id)
    end

    it 'consults plugins in registration order when they supply the same value' do
      model = define_model('PluginOrderUser', name: :string, nickname: :string)
      FactoryBakery.register_plugin(plugin_with(heuristics: ->(*) { { 'nickname' => 'first' } }))
      FactoryBakery.register_plugin(plugin_with(heuristics: ->(*) { { 'nickname' => 'second' } }))

      expect(FactoryBakery.bake(model).nickname).to eq('second')
    end

    it 'keeps a plugin-supplied polymorphic type/id pair together' do
      post_model = define_model('PolyPluginPost', title: :string)
      model = define_model('PolyPluginComment', commentable_type: :string, commentable_id: :integer) do
        belongs_to :commentable, polymorphic: true, optional: true
      end
      post = post_model.create!(title: 't')
      FactoryBakery.register_plugin(
        plugin_with(
          heuristics: ->(*) { { 'commentable_type' => 'PolyPluginPost', 'commentable_id' => post.id } }
        )
      )

      record = FactoryBakery.bake(model)

      expect([record.commentable_type, record.commentable_id]).to eq(['PolyPluginPost', post.id])
    end
  end

  describe 'the after_instantiate hook' do
    it 'runs after plain values are applied, in registration order' do
      model = define_model('AfterHookUser', name: :string, nickname: :string)
      order = []
      first = plugin_with(
        dsl: recording_dsl(:shout),
        after: lambda do |object, declarations, _context|
          order << [:first, object.name]
          object.nickname = "decls=#{declarations.inspect}"
        end
      )
      second = plugin_with(
        after: lambda do |object, _declarations, _context|
          order << [:second, object.name]
        end
      )
      FactoryBakery.register_plugin(first)
      FactoryBakery.register_plugin(second)
      FactoryBakery.define(model) do
        name { 'ann' }
        shout :name
      end

      record = FactoryBakery.bake(model)

      expect(order).to eq([[:first, 'ann'], [:second, 'ann']])
      expect(record.nickname).to eq('decls=[:name]')
    end

    it 'receives its own declaration bucket and the build context' do
      model = define_model('AfterContextUser', name: :string)
      captured = nil
      plugin = plugin_with(
        dsl: recording_dsl(:shout),
        after: lambda do |object, declarations, context|
          captured = { object: object, declarations: declarations.dup, path: context.path, depth: context.depth }
        end
      )
      FactoryBakery.register_plugin(plugin)
      FactoryBakery.define(model) do
        name { 'ann' }
        shout :name
      end

      record = FactoryBakery.bake(model)

      expect(captured[:object]).to equal(record)
      expect(captured[:declarations]).to eq([:name])
      expect(captured[:path]).to eq([model])
      expect(captured[:depth]).to eq(1)
    end
  end

  describe 'registration lifecycle' do
    it 'is idempotent per plugin object' do
      model = define_model('IdempotentPluginUser', name: :string)
      calls = 0
      plugin = plugin_with(
        dsl: recording_dsl(:shout),
        after: lambda do |_object, _declarations, _context|
          calls += 1
        end
      )
      FactoryBakery.register_plugin(plugin)
      FactoryBakery.register_plugin(plugin)
      FactoryBakery.define(model) do
        name { 'ann' }
        shout :name
      end

      FactoryBakery.bake(model)

      expect(calls).to eq(1)
    end

    it 'can unregister and reset plugins between examples' do
      model = define_model('LifecyclePluginUser', name: :string, nickname: :string)
      plugin = plugin_with(
        heuristics: ->(_klass, _context, _taken) { { 'nickname' => 'from-plugin' } }
      )
      FactoryBakery.register_plugin(plugin)
      expect(FactoryBakery.bake(model).nickname).to eq('from-plugin')

      FactoryBakery.unregister_plugin(plugin)
      expect(FactoryBakery.bake(model).nickname).not_to eq('from-plugin')

      FactoryBakery.register_plugin(plugin)
      FactoryBakery.reset_plugins!
      expect(FactoryBakery.bake(model).nickname).not_to eq('from-plugin')
    end

    it 'stops offering a plugin DSL method once the plugin is unregistered, after bakes already used it' do
      model = define_model('DslLifecycleUser', name: :string, nickname: :string)
      plugin = plugin_with(dsl: recording_dsl(:nickname_tag), after: uppercasing_after)
      FactoryBakery.register_plugin(plugin)
      FactoryBakery.define(model) { nickname_tag 'nickname' }
      expect { FactoryBakery.bake(model, nickname: 'ada') }.not_to raise_error

      FactoryBakery.unregister_plugin(plugin)

      expect { FactoryBakery.bake(model) }.to raise_error(FactoryBakery::Error, /Use nickname_tag|Static attributes/)
    end

    it 'offers a DSL method of a plugin registered after earlier bakes' do
      model = define_model('DslLateUser', name: :string, nickname: :string)
      FactoryBakery.bake(model)
      FactoryBakery.register_plugin(plugin_with(dsl: recording_dsl(:nickname_tag), after: uppercasing_after))
      FactoryBakery.define(model) { nickname_tag 'nickname' }

      expect(FactoryBakery.bake(model, nickname: 'ada').nickname).to eq('ADA')
    end

    it 'leaves the no-plugin path unchanged' do
      model = define_model('NoPluginUser', name: :string, city: :string)
      FactoryBakery.define(model) do
        name { 'from-factory' }
        trait :cairo do
          city { 'from-trait' }
        end
      end

      record = FactoryBakery.bake(model, :cairo, name: 'from-call-site')

      expect([record.name, record.city]).to eq(['from-call-site', 'from-trait'])
    end
  end
end
