# frozen_string_literal: true

require 'spec_helper'
require 'active_support/notifications'
require 'factory_bakery/associations'

# Bounded :all graph behavior: the dependency graph is shared (one object per
# completed class), optional edges are best-effort, cycles only stop required
# edges, HABTM plumbing is skipped, and an edge whose child cannot be wired to
# an unsaved owner is left empty. Every assertion goes through define/bake/bake!
# and the models' public association API -- never builder internals.
RSpec.describe 'FactoryBakery associations :all bounded graph' do
  before do
    FactoryBakery.reset_plugins!
    FactoryBakery.register_plugin(FactoryBakery::Associations::Plugin)
    FactoryBakery::Associations.mode = :all
    FactoryBakery::Associations.max_depth = 2
    FactoryBakery::Associations.default_count = 1
  end

  after do
    FactoryBakery.reset_plugins!
    FactoryBakery::Associations.reset_configuration!
  end

  describe 'in-graph identity (B1)' do
    # Comment belongs_to :post and :user; Post belongs_to :user. All required.
    def define_comment_graph(prefix)
      user = define_model("#{prefix}User", name: :string)
      post = define_model("#{prefix}Post", title: :string, user_id: :integer) do
        belongs_to :user, class_name: "#{prefix}User", optional: false
      end
      comment = define_model("#{prefix}Comment", body: :string, post_id: :integer, user_id: :integer) do
        belongs_to :post, class_name: "#{prefix}Post", optional: false
        belongs_to :user, class_name: "#{prefix}User", optional: false
      end
      [user, post, comment]
    end

    it 'assigns the completed user instead of building a second one' do
      user_model, _post, comment_model = define_comment_graph('BoundUser')

      comment = FactoryBakery.bake(comment_model)

      expect(comment.user).to equal(comment.post.user)
      expect(user_model.count).to eq(0)
    end

    it 'does not share when the owner foreign key is uniqueness-validated' do
      _user, _post, comment_model = define_comment_graph('BoundUnique')
      comment_model.validates :user_id, uniqueness: true

      comment = FactoryBakery.bake(comment_model)

      expect(comment.user).not_to equal(comment.post.user)
    end

    it 'still gives a raw-FK-presence edge its own persisted parent' do
      define_model('BoundFKUser', name: :string)
      order_model = define_model('BoundFKOrder', user_id: :integer, reviewer_id: :integer) do
        belongs_to :user, class_name: 'BoundFKUser', optional: false
        belongs_to :reviewer, class_name: 'BoundFKUser', optional: false
        validates :reviewer_id, presence: true
      end

      order = FactoryBakery.bake!(order_model)

      expect(order.reviewer_id).not_to be_nil
      expect(order.user).not_to equal(order.reviewer)
    end

    it 'shares an already persisted parent across raw-FK-presence edges' do
      user_model = define_model('BoundFKShareUser', name: :string)
      define_model('BoundFKShareShop', user_id: :integer) do
        belongs_to :user, class_name: 'BoundFKShareUser', optional: false
        validates :user_id, presence: true
      end
      order_model = define_model('BoundFKShareOrder', shop_id: :integer, user_id: :integer) do
        belongs_to :shop, class_name: 'BoundFKShareShop', optional: false
        belongs_to :user, class_name: 'BoundFKShareUser', optional: false
        validates :shop_id, :user_id, presence: true
      end

      order = FactoryBakery.bake!(order_model)

      expect(order.user_id).to eq(order.shop.user_id)
      expect(user_model.count).to eq(1)
    end

    it 'never shares one object between two edges of the same owner' do
      user_model = define_model('BoundPairUser', name: :string)
      transfer_model = define_model('BoundPairTransfer', sender_id: :integer, receiver_id: :integer) do
        belongs_to :sender, class_name: 'BoundPairUser', optional: false
        belongs_to :receiver, class_name: 'BoundPairUser', optional: false
      end

      transfer = FactoryBakery.bake!(transfer_model)

      expect(transfer.sender).not_to equal(transfer.receiver)
      expect(user_model.count).to eq(2)
    end
  end

  describe 'optional edges are best-effort (B2)' do
    it 'skips an optional belongs_to with a missing foreign key and keeps a writable sibling' do
      parent = define_model('BoundWritableParent', name: :string)
      child = define_model('BoundMissingForeignKey', title: :string, parent_id: :integer) do
        belongs_to :retired_parent, class_name: 'BoundWritableParent', optional: true
        belongs_to :parent, class_name: 'BoundWritableParent', optional: true
      end

      record = FactoryBakery.bake!(child).reload

      expect(record.parent).to be_persisted
      expect(parent.count).to eq(1)
    end

    it 'leaves a has_many empty when every child is invalid' do
      define_model('BoundBadPost', title: :string, author_id: :integer) do
        belongs_to :author, class_name: 'BoundBadAuthor', optional: true
        validate :always_invalid
        def always_invalid
          errors.add(:base, 'never valid')
        end
      end
      author_model = define_model('BoundBadAuthor', name: :string) do
        has_many :posts, class_name: 'BoundBadPost', inverse_of: :author
      end

      author = FactoryBakery.bake!(author_model)

      expect(author.posts).to be_empty
      expect(Object.const_get('BoundBadPost').count).to eq(0)
    end

    it 'leaves an optional has_one nil when its child is invalid' do
      define_model('BoundBadProfile', bio: :string, user_id: :integer) do
        belongs_to :user, class_name: 'BoundBadUser', optional: true
        validate :always_invalid
        def always_invalid
          errors.add(:base, 'never valid')
        end
      end
      user_model = define_model('BoundBadUser', name: :string) do
        has_one :profile, class_name: 'BoundBadProfile', inverse_of: :user
      end

      user = FactoryBakery.bake!(user_model)

      expect(user.profile).to be_nil
      expect(Object.const_get('BoundBadProfile').count).to eq(0)
    end

    it 'leaves an optional belongs_to nil when its target raises' do
      define_model('BoundRaiseTarget', name: :string)
      FactoryBakery.define(Object.const_get('BoundRaiseTarget')) do
        name { raise 'target declaration boom' }
      end
      holder_model = define_model('BoundRaiseHolder', title: :string, target_id: :integer) do
        belongs_to :target, class_name: 'BoundRaiseTarget', optional: true
      end

      holder = FactoryBakery.bake!(holder_model)

      expect(holder.target).to be_nil
    end

    it 'keeps raising for a required edge whose target raises' do
      define_model('BoundRequiredRaiseTarget', name: :string)
      FactoryBakery.define(Object.const_get('BoundRequiredRaiseTarget')) do
        name { raise 'required target boom' }
      end
      holder_model = define_model('BoundRequiredRaiseHolder', title: :string, target_id: :integer) do
        belongs_to :target, class_name: 'BoundRequiredRaiseTarget', optional: false
      end

      expect { FactoryBakery.bake(holder_model) }.to raise_error(RuntimeError, /required target boom/)
    end
  end

  describe 'cycles (B3)' do
    it 'skips an optional self-reference instead of recursing' do
      node_model = define_model('BoundNode', name: :string, parent_id: :integer) do
        belongs_to :parent, class_name: 'BoundNode', optional: true
      end

      node = FactoryBakery.bake!(node_model)

      expect(node.parent).to be_nil
    end

    it 'still raises for a required self-reference' do
      node_model = define_model('BoundRequiredNode', name: :string, parent_id: :integer) do
        belongs_to :parent, class_name: 'BoundRequiredNode', optional: false
      end

      expect { FactoryBakery.bake(node_model) }
        .to raise_error(FactoryBakery::CyclicAssociationError, /BoundRequiredNode#parent/)
    end
  end

  describe 'HABTM plumbing (B4)' do
    def define_habtm(prefix)
      table = "#{prefix.underscore}_posts_tags"
      create_table(table) do |join_table|
        join_table.integer :bound_habtm_post_id
        join_table.integer :bound_habtm_tag_id
      end
      define_model("#{prefix}Tag", name: :string)
      define_model("#{prefix}Post", title: :string) do
        has_and_belongs_to_many :tags, class_name: "#{prefix}Tag", join_table: table
      end
    end

    it 'bakes the owner in :all without building the anonymous join model' do
      post_model = define_habtm('BoundHABTM')

      expect { FactoryBakery.bake!(post_model) }.not_to raise_error
    end

    it 'bakes the join class directly with both foreign keys set' do
      post_model = define_habtm('BoundHABTM')
      join_model = post_model.const_get(:HABTM_Tags)

      join = FactoryBakery.bake!(join_model)

      expect(join.bound_habtm_post_id).not_to be_nil
      expect(join.bound_habtm_tag_id).not_to be_nil
      expect(join).to be_persisted
    end
  end

  describe 'unverified inverse with a required back-reference (B5)' do
    it 'leaves the collection empty instead of failing with "Owner must exist"' do
      define_model('BoundItem', title: :string, owner_id: :integer) do
        belongs_to :owner, class_name: 'BoundOwner', optional: false
      end
      owner_model = define_model('BoundOwner', name: :string) do
        has_many :items, class_name: 'BoundItem', foreign_key: :owner_id, inverse_of: false
      end

      owner = FactoryBakery.bake!(owner_model)

      expect(owner.items).to be_empty
      expect(Object.const_get('BoundItem').count).to eq(0)
    end
  end

  describe 'optional child whose required parent cannot be made valid (B6)' do
    # Discourse: an optional :all child (McpOauthAuthorization) requires a
    # parent (McpOauthClient) that bakes invalid. The child is valid on its own,
    # because a required belongs_to accepts any parent object, but inserting it
    # would skip the invalid parent and write a nil foreign key.
    def define_broken_parent_graph(prefix)
      define_model("#{prefix}Client", name: :string) do
        validate { errors.add(:base, 'needs app knowledge') }
      end
      grant = define_model("#{prefix}Grant", note: :string, owner_id: :integer, client_id: :integer) do
        belongs_to :owner, class_name: "#{prefix}Owner", optional: false
        belongs_to :client, class_name: "#{prefix}Client", optional: false
      end
      owner = define_model("#{prefix}Owner", name: :string) do
        has_many :grants, class_name: "#{prefix}Grant", foreign_key: :owner_id, inverse_of: :owner
      end
      [owner, grant]
    end

    it 'drops the optional collection instead of inserting a nil foreign key' do
      owner_model, grant_model = define_broken_parent_graph('BoundBrokenParent')

      owner = FactoryBakery.bake!(owner_model)

      expect(owner).to be_persisted
      expect(owner.grants).to be_empty
      expect(grant_model.where(client_id: nil).count).to eq(0)
    end

    it 'keeps an optional child whose required parents are valid' do
      define_model('BoundFineClient', name: :string)
      define_model('BoundFineGrant', owner_id: :integer, client_id: :integer) do
        belongs_to :owner, class_name: 'BoundFineOwner', optional: false
        belongs_to :client, class_name: 'BoundFineClient', optional: false
      end
      owner_model = define_model('BoundFineOwner', name: :string) do
        has_many :grants, class_name: 'BoundFineGrant', foreign_key: :owner_id, inverse_of: :owner
      end

      grant = FactoryBakery.bake!(owner_model).grants.first

      expect(grant).to be_persisted
      expect(grant.client).to be_persisted
    end
  end
end
