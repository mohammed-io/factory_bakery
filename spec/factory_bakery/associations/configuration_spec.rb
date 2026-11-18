# frozen_string_literal: true

require 'spec_helper'
require 'factory_bakery/associations'

# Public-API behavior for A14: global configuration is validated, and
# Associations.with applies overrides to the whole nested graph for one scope.
# Every assertion goes through define/bake or the plugin's public config API;
# builder internals are deliberately out of scope.
RSpec.describe 'FactoryBakery associations configuration' do
  before do
    FactoryBakery.reset_plugins!
    FactoryBakery.register_plugin(FactoryBakery::Associations::Plugin)
    FactoryBakery::Associations.reset_configuration!
  end

  after do
    FactoryBakery.reset_plugins!
    FactoryBakery::Associations.reset_configuration!
  end

  def define_user_and_account(prefix, optional: true)
    account = define_model("#{prefix}Account", name: :string)
    user = define_model("#{prefix}User", name: :string, account_id: :integer) do
      belongs_to :account, class_name: "#{prefix}Account", optional: optional
    end
    [account, user]
  end

  # Author has_many :posts; Post belongs_to :author (optional) and has_many
  # :comments; Comment belongs_to :post (required) and :editor (optional).
  def define_graph(prefix)
    define_model("#{prefix}User", name: :string)
    define_model("#{prefix}Comment", body: :string, post_id: :integer, editor_id: :integer) do
      belongs_to :post, class_name: "#{prefix}Post", optional: false
      belongs_to :editor, class_name: "#{prefix}User", optional: true
    end
    define_model("#{prefix}Post", title: :string, author_id: :integer) do
      belongs_to :author, class_name: "#{prefix}Author", optional: true
      has_many :comments, class_name: "#{prefix}Comment", inverse_of: :post
    end
    author = define_model("#{prefix}Author", name: :string) do
      has_many :posts, class_name: "#{prefix}Post", inverse_of: :author
    end
    [author, Object.const_get("#{prefix}Post")]
  end

  describe 'effective configuration' do
    it 'reports the global defaults with no scope active' do
      expect(FactoryBakery::Associations.mode).to eq(:required_only)
      expect(FactoryBakery::Associations.max_depth).to eq(2)
      expect(FactoryBakery::Associations.default_count).to eq(1)
    end

    it 'reports scoped values inside the block and global values outside it' do
      FactoryBakery::Associations.mode = :none
      FactoryBakery::Associations.max_depth = 2
      FactoryBakery::Associations.default_count = 1

      inside = FactoryBakery::Associations.with(mode: :all, max_depth: 3, default_count: 4) do
        [FactoryBakery::Associations.mode, FactoryBakery::Associations.max_depth,
         FactoryBakery::Associations.default_count]
      end

      expect(inside).to eq([:all, 3, 4])
      expect([FactoryBakery::Associations.mode, FactoryBakery::Associations.max_depth,
              FactoryBakery::Associations.default_count]).to eq([:none, 2, 1])
    end
  end

  describe 'Associations.with' do
    it 'returns the value of the block' do
      expect(FactoryBakery::Associations.with(mode: :none) { :result }).to eq(:result)
    end

    it 'applies a scoped :all mode to the graph baked inside the block' do
      account, user = define_user_and_account('ScopedAll')
      FactoryBakery::Associations.mode = :none

      scoped = FactoryBakery::Associations.with(mode: :all) { FactoryBakery.bake(user) }
      outside = FactoryBakery.bake(user)

      expect(scoped.account).to be_a(account)
      expect(outside.account).to be_nil
      expect(FactoryBakery::Associations.mode).to eq(:none)
    end

    it 'applies a scoped :none mode over a global :required_only mode' do
      account, user = define_user_and_account('ScopedNone', optional: false)
      FactoryBakery::Associations.mode = :required_only

      inside = FactoryBakery::Associations.with(mode: :none) do
        expect(FactoryBakery.bake(user).account).to be_nil
        FactoryBakery::Associations.with(mode: :required_only) do
          FactoryBakery.bake(user).account.class
        end
      end

      expect(inside).to eq(account)
      expect(FactoryBakery.bake(user).account).to be_a(account)
      expect(FactoryBakery::Associations.mode).to eq(:required_only)
    end

    it 'restores the global mode when the block raises' do
      _account, user = define_user_and_account('ScopedRaise', optional: false)
      FactoryBakery::Associations.mode = :required_only

      expect do
        FactoryBakery::Associations.with(mode: :none) do
          expect(FactoryBakery.bake(user).account).to be_nil
          raise 'boom'
        end
      end.to raise_error(RuntimeError, 'boom')

      expect(FactoryBakery::Associations.mode).to eq(:required_only)
      expect(FactoryBakery.bake(user).account).not_to be_nil
    end

    it 'lets an inner scope win and restores the outer scope afterwards' do
      account, user = define_user_and_account('ScopedNested')

      FactoryBakery::Associations.with(mode: :none) do
        expect(FactoryBakery.bake(user).account).to be_nil

        FactoryBakery::Associations.with(mode: :all) do
          expect(FactoryBakery.bake(user).account).to be_a(account)
        end

        expect(FactoryBakery::Associations.mode).to eq(:none)
        expect(FactoryBakery.bake(user).account).to be_nil
      end

      expect(FactoryBakery::Associations.mode).to eq(:required_only)
    end

    it 'honors scoped max_depth for bakes inside the block' do
      author_model, = define_graph('ScopedDepth')
      FactoryBakery::Associations.mode = :all
      FactoryBakery::Associations.max_depth = 2

      shallow = FactoryBakery::Associations.with(max_depth: 1) { FactoryBakery.bake(author_model) }
      deep = FactoryBakery.bake(author_model)

      expect(shallow.posts.first.comments).to be_empty
      expect(deep.posts.first.comments.size).to eq(1)
      expect(FactoryBakery::Associations.max_depth).to eq(2)
    end

    it 'honors scoped default_count for bakes inside the block' do
      author_model, = define_graph('ScopedCount')
      FactoryBakery::Associations.mode = :all

      scoped = FactoryBakery::Associations.with(default_count: 3) { FactoryBakery.bake(author_model) }
      outside = FactoryBakery.bake(author_model)

      expect(scoped.posts.size).to eq(3)
      expect(outside.posts.size).to eq(1)
      expect(FactoryBakery::Associations.default_count).to eq(1)
    end

    it 'applies to bakes made from declaration blocks in the same graph' do
      account, user = define_user_and_account('ScopedDeclBlock')
      wrapper = define_model('ScopedDeclBlockWrapper', name: :string, user_id: :integer) do
        belongs_to :user, class_name: 'ScopedDeclBlockUser', optional: true
      end
      FactoryBakery.define(wrapper) { user { FactoryBakery.bake(user) } }

      FactoryBakery::Associations.with(mode: :all) do
        expect(FactoryBakery.bake(wrapper).user.account).to be_a(account)
      end
      expect(FactoryBakery.bake(wrapper).user.account).to be_nil
    end

    it 'keeps sibling threads isolated' do
      entered = Queue.new
      release = Queue.new
      thread = Thread.new do
        FactoryBakery::Associations.with(mode: :none) do
          entered << true
          release.pop
          FactoryBakery::Associations.mode
        end
      end

      begin
        entered.pop
        expect(FactoryBakery::Associations.mode).to eq(:required_only)
      ensure
        release << true
      end

      expect(thread.value).to eq(:none)
      expect(FactoryBakery::Associations.mode).to eq(:required_only)
    end

    it 'keeps sibling fibers isolated and does not leak a child fiber scope to its parent' do
      inside = FactoryBakery::Associations.with(mode: :all) do
        Fiber.new do
          [FactoryBakery::Associations.mode,
           FactoryBakery::Associations.with(mode: :none) { FactoryBakery::Associations.mode },
           FactoryBakery::Associations.mode]
        end.resume
      end
      expect(inside).to eq(%i[all none all])

      scoped = Fiber.new { FactoryBakery::Associations.with(mode: :none) { :ok } }
      other = Fiber.new { FactoryBakery::Associations.mode }
      scoped.resume
      expect(other.resume).to eq(:required_only)
      expect(FactoryBakery::Associations.mode).to eq(:required_only)
    end
  end

  describe 'validation' do
    it 'validates global settings with clear ArgumentError messages' do
      expect { FactoryBakery::Associations.mode = :everything }
        .to raise_error(ArgumentError, /everything/)
      expect { FactoryBakery::Associations.max_depth = -1 }
        .to raise_error(ArgumentError, /max_depth/)
      expect { FactoryBakery::Associations.default_count = '2' }
        .to raise_error(ArgumentError, /default_count/)
    end

    it 'rejects unknown scope keys and values with ArgumentError' do
      expect { FactoryBakery::Associations.with(mode: :everything) {} }
        .to raise_error(ArgumentError, /everything/)
      expect { FactoryBakery::Associations.with(max_depth: -1) {} }
        .to raise_error(ArgumentError, /max_depth/)
      expect { FactoryBakery::Associations.with(default_count: 1.5) {} }
        .to raise_error(ArgumentError, /default_count/)
      expect { FactoryBakery::Associations.with(strategy: :reuse) {} }
        .to raise_error(ArgumentError, /strategy/)
    end

    it 'applies none of a scope whose validation fails' do
      FactoryBakery::Associations.mode = :none
      expect { FactoryBakery::Associations.with(mode: :all, max_depth: -1) {} }
        .to raise_error(ArgumentError)

      expect(FactoryBakery::Associations.mode).to eq(:none)
      expect(FactoryBakery::Associations.max_depth).to eq(2)
    end

    it 'leaves an outer scope intact when a nested scope is rejected' do
      FactoryBakery::Associations.with(mode: :all, max_depth: 3) do
        expect { FactoryBakery::Associations.with(mode: :bogus) {} }
          .to raise_error(ArgumentError)

        expect(FactoryBakery::Associations.mode).to eq(:all)
        expect(FactoryBakery::Associations.max_depth).to eq(3)
      end

      expect(FactoryBakery::Associations.mode).to eq(:required_only)
    end
  end
end
