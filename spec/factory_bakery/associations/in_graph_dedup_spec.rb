# frozen_string_literal: true

require 'spec_helper'
require 'factory_bakery/associations'

# A16: in-graph sharing under :reuse_non_unique (diamond dedup). Every assertion goes
# through define/bake/bake! or the plugin's public configuration API.
RSpec.describe 'in-graph sharing under :reuse_non_unique' do
  before do
    FactoryBakery.reset_plugins!
    FactoryBakery.register_plugin(FactoryBakery::Associations::Plugin)
    FactoryBakery::Associations.reset_configuration!
  end

  after do
    FactoryBakery.reset_plugins!
    FactoryBakery::Associations.reset_configuration!
  end

  # Order belongs_to :user and :shop (both required); Shop belongs_to :user.
  def define_order_graph(prefix)
    user = define_model("#{prefix}User", name: :string)
    shop = define_model("#{prefix}Shop", user_id: :integer) do
      belongs_to :user, class_name: "#{prefix}User", optional: false
    end
    order = define_model("#{prefix}Order", user_id: :integer, shop_id: :integer) do
      belongs_to :user, class_name: "#{prefix}User", optional: false
      belongs_to :shop, class_name: "#{prefix}Shop", optional: false
    end
    [user, shop, order]
  end

  describe 'the diamond' do
    it 'shares one parent across two paths in a graph even when the table is empty' do
      _user, _shop, order = define_order_graph('DedupDiamond')

      baked = FactoryBakery::Associations.with(strategy: :reuse_non_unique) { FactoryBakery.bake(order) }

      expect(baked.user).to equal(baked.shop.user)
    end

    it 'persists the shared parent exactly once under bake!' do
      user, _shop, order = define_order_graph('DedupBang')

      FactoryBakery::Associations.with(strategy: :reuse_non_unique) { FactoryBakery.bake!(order) }

      expect(user.count).to eq(1)
    end

    it 'starts with an empty graph for each separate top-level bake' do
      _user, _shop, order = define_order_graph('DedupSeparate')

      first, second = FactoryBakery::Associations.with(strategy: :reuse_non_unique) do
        [FactoryBakery.bake(order), FactoryBakery.bake(order)]
      end

      expect(first.user).not_to equal(second.user)
    end

    it 'shares a completed parent under the default :fresh strategy too (in-graph identity)' do
      _user, _shop, order = define_order_graph('DedupFresh')

      baked = FactoryBakery.bake(order)

      expect(baked.user).to equal(baked.shop.user)
    end
  end

  describe 'match strictness' do
    it 'shares two distinct declaration names targeting the same class and options' do
      agent = define_model('DedupAgent', name: :string)
      task = define_model('DedupTask', creator_id: :integer, assignee_id: :integer) do
        belongs_to :creator, class_name: 'DedupAgent', optional: false
        belongs_to :assignee, class_name: 'DedupAgent', optional: false
      end
      FactoryBakery.define(task) do
        association :creator, strategy: :reuse_non_unique
        association :assignee, strategy: :reuse_non_unique
      end

      baked = FactoryBakery.bake(task)

      expect(baked.creator).to equal(baked.assignee)
      expect(agent.count).to eq(0)
    end

    it 'does not share objects whose scalar overrides differ' do
      define_model('DedupPerson', name: :string)
      post = define_model('DedupPost', author_id: :integer, editor_id: :integer) do
        belongs_to :author, class_name: 'DedupPerson', optional: false
        belongs_to :editor, class_name: 'DedupPerson', optional: false
      end
      FactoryBakery.define(post) do
        association :author, strategy: :reuse_non_unique, name: 'Author'
        association :editor, strategy: :reuse_non_unique, name: 'Editor'
      end

      baked = FactoryBakery.bake(post)

      expect(baked.author).not_to equal(baked.editor)
      expect([baked.author.name, baked.editor.name]).to eq(%w[Author Editor])
    end

    it 'does not share objects of a different exact class' do
      base = define_model('DedupVehicle', name: :string, type: :string)
      car = define_class('DedupCar', base)
      trip = define_model('DedupTrip', vehicle_id: :integer, car_id: :integer) do
        belongs_to :vehicle, class_name: 'DedupVehicle', optional: false
        belongs_to :car, class_name: 'DedupCar', optional: false
      end

      baked = FactoryBakery::Associations.with(strategy: :reuse_non_unique) { FactoryBakery.bake(trip) }

      expect(baked.vehicle).not_to equal(baked.car)
      expect(baked.vehicle.class).not_to eq(baked.car.class)
      expect(baked.car).to be_a(car)
    end

    it 'does not share objects matched under different association scopes' do
      define_model('DedupScopedAccount', name: :string, active: :boolean)
      profile = define_model('DedupScopedProfile', active_account_id: :integer, archived_account_id: :integer) do
        belongs_to :active_account, -> { where(active: true) },
                   class_name: 'DedupScopedAccount', optional: false
        belongs_to :archived_account, -> { where(active: false) },
                   class_name: 'DedupScopedAccount', optional: false
      end

      baked = FactoryBakery::Associations.with(strategy: :reuse_non_unique) { FactoryBakery.bake(profile) }

      expect(baked.active_account).not_to equal(baked.archived_account)
    end
  end

  describe 'guards' do
    it 'does not share an ancestor that is still being built' do
      user = define_model('DedupCycleUser', name: :string)
      define_model('DedupCycleAccount', user_id: :integer) do
        belongs_to :user, class_name: 'DedupCycleUser', optional: false
      end
      user.class_eval do
        belongs_to :account, class_name: 'DedupCycleAccount', optional: false
      end

      expect do
        FactoryBakery::Associations.with(strategy: :reuse_non_unique) { FactoryBakery.bake!(user) }
      end.to raise_error(FactoryBakery::CyclicAssociationError, /DedupCycleUser#account/)
    end

    it 'keeps the nesting backstop intact under reuse_non_unique' do
      node = define_model('DedupNode', name: :string, parent_id: :integer) do
        belongs_to :parent, class_name: 'DedupNode', optional: false
      end
      # A self-reference declared explicitly never repeats a reflection path, so
      # the core depth backstop -- not the reflection cycle detector -- owns it.
      FactoryBakery.define(node) do
        association :parent, strategy: :reuse_non_unique
      end

      expect do
        FactoryBakery::Associations.with(strategy: :reuse_non_unique) { FactoryBakery.bake(node) }
      end.to raise_error(FactoryBakery::NestingTooDeepError, /max_bake_depth/)
    end
  end
end
