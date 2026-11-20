# frozen_string_literal: true

require 'spec_helper'
require 'factory_bakery/associations'

# Two real-app `:all` failures found by baking every Discourse/Mastodon model:
#
#   * Discourse declares `Topic has_many :user_profiles`, but `user_profiles`
#     has no `topic_id` column. Building the child wrote an unknown attribute
#     (`ActiveModel::MissingAttributeError: can't write unknown attribute
#     `topic_id'`).
#   * Mastodon's `User has_many :ips` targets `UserIp`, a database view
#     (`readonly?` true). `bake!` refused the graph with ReadOnlyTargetError
#     even though the edge is optional.
#
# Both are skipped the way any failed optional edge is: the association is left
# unloaded/empty and the bake succeeds. Reading `record.things` directly would
# query a table whose foreign key column does not exist, so these examples
# assert on the association's loaded state instead.
RSpec.describe 'FactoryBakery associations :all dead and read-only edges' do
  before do
    FactoryBakery.reset_plugins!
    FactoryBakery.register_plugin(FactoryBakery::Associations::Plugin)
    FactoryBakery::Associations.mode = :all
  end

  after do
    FactoryBakery.reset_plugins!
    FactoryBakery::Associations.reset_configuration!
  end

  describe 'a has_many whose target has no foreign key column' do
    it 'is skipped and the owner still bakes (and persists) under bake!' do
      define_model('DeadFkThing', name: :string)
      topic = define_model('DeadFkTopic', title: { type: :string, null: false }) do
        has_many :things, class_name: 'DeadFkThing'
      end

      record = FactoryBakery.bake!(topic)

      expect(record).to be_persisted
      expect(record.association(:things)).not_to be_loaded
      expect(topic.count).to eq(1)
      expect(Object.const_get('DeadFkThing').count).to eq(0)
    end

    it 'is skipped under plain bake too' do
      define_model('DeadFkThing', name: :string)
      topic = define_model('DeadFkTopic', title: :string) do
        has_many :things, class_name: 'DeadFkThing'
      end

      record = FactoryBakery.bake(topic)

      expect(record.association(:things)).not_to be_loaded
      expect(record).to be_valid
    end

    it 'keeps building a sibling has_many whose foreign key does exist' do
      define_model('DeadFkThing', name: :string)
      define_model('DeadFkComment', body: :string, topic_id: :integer) do
        belongs_to :topic, class_name: 'DeadFkTopic', optional: false
      end
      topic = define_model('DeadFkTopic', title: :string) do
        has_many :things, class_name: 'DeadFkThing'
        has_many :comments, class_name: 'DeadFkComment', inverse_of: :topic
      end

      record = FactoryBakery.bake(topic)

      expect(record.association(:things)).not_to be_loaded
      expect(record.comments.size).to eq(1)
    end
  end

  describe 'an optional has_many whose target is read-only' do
    def define_view_and_owner(prefix)
      define_model("#{prefix}Ip", address: :string, "#{prefix}user_id": :integer) do
        define_method(:readonly?) { true }
      end
      owner = define_model("#{prefix}User", name: :string) do
        has_many :ips, class_name: "#{prefix}Ip"
      end
      [Object.const_get("#{prefix}Ip"), owner]
    end

    it 'leaves the collection empty and persists the owner under bake!' do
      ip, owner = define_view_and_owner('DeadRoUser')

      record = FactoryBakery.bake!(owner)

      expect(record).to be_persisted
      expect(ip.where(id: ip.select(:id)).to_a).to be_empty
      expect(owner.count).to eq(1)
    end

    it 'leaves the collection empty under plain bake' do
      _ip, owner = define_view_and_owner('DeadRoPlain')

      record = FactoryBakery.bake(owner)

      expect(record.ips).to be_empty
      expect(record).to be_valid
    end

    it 'does not let a read-only has_one sibling fail the bake either' do
      define_model('DeadRoProfile', bio: :string, dead_ro_owner_id: :integer) do
        define_method(:readonly?) { true }
      end
      owner = define_model('DeadRoOwner', name: :string) do
        has_one :profile, class_name: 'DeadRoProfile'
      end

      record = FactoryBakery.bake!(owner)

      expect(record.profile).to be_nil
      expect(record).to be_persisted
    end
  end
end
