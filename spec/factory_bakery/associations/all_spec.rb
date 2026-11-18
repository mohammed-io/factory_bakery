# frozen_string_literal: true

require 'spec_helper'
require 'active_support/notifications'
require 'factory_bakery/associations'

# Public-API behavior for A13: the :all mode builds every direct association
# within a depth budget, never walks back the edge it came from, and truncates
# to :required_only past the budget. Every assertion goes through
# define/bake/bake!, row counts, SQL INSERT notifications and the plugin's
# public configuration -- never builder internals.
RSpec.describe 'FactoryBakery associations :all mode' do
  before do
    FactoryBakery.reset_plugins!
    FactoryBakery.register_plugin(FactoryBakery::Associations::Plugin)
    FactoryBakery::Associations.mode = :all
    FactoryBakery::Associations.max_depth = 2
    FactoryBakery::Associations.default_count = 1
  end

  after do
    FactoryBakery.reset_plugins!
    FactoryBakery::Associations.mode = :required_only
    FactoryBakery::Associations.max_depth = 2
    FactoryBakery::Associations.default_count = 1
  end

  def inserts_in
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, _start, _finish, _id, payload|
      count += 1 if payload[:sql].start_with?('INSERT')
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  # Author has_many :posts; Post belongs_to :author (optional) and has_many
  # :comments; Comment belongs_to :post (required) and :editor (optional).
  def define_graph(prefix)
    define_model("#{prefix}User", name: :string)
    define_model("#{prefix}Comment",
                 body: :string, post_id: :integer, editor_id: :integer) do
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
    [author, Object.const_get("#{prefix}Post"), Object.const_get("#{prefix}Comment")]
  end

  describe 'kinds built in :all' do
    it 'builds an optional belongs_to with the parent class and factory heuristics' do
      author_model, post_model, = define_graph('AllOptional')
      FactoryBakery.define(author_model) { name { 'from factory' } }

      post = FactoryBakery.bake(post_model)

      expect(post.author).to be_a(author_model)
      expect(post.author.name).to eq('from factory')
      expect(post.author).to be_new_record
    end

    it 'builds a required belongs_to just as :required_only does' do
      _author, _post, comment_model = define_graph('AllRequired')
      # Comment#post is required; the graph's post #comments is declared so the
      # comment is reached through a collection and gets its owner bound.
      post_model = Object.const_get('AllRequiredPost')
      post = FactoryBakery.bake!(post_model)

      expect(post.comments.first.post).to equal(post)
      expect(comment_model.count).to eq(1)
    end

    it 'builds one has_one child bound to the owner' do
      profile_model = define_model('AllProfile', bio: :string, user_id: :integer) do
        belongs_to :user, class_name: 'AllHasOneUser', optional: false
      end
      user_model = define_model('AllHasOneUser', name: :string) do
        has_one :profile, class_name: 'AllProfile', inverse_of: :user
      end

      user = FactoryBakery.bake(user_model)

      expect(user.profile).to be_a(profile_model)
      expect(user.profile.user).to equal(user)
    end

    it 'builds has_many children using default_count' do
      author_model, post_model, = define_graph('AllCollection')
      FactoryBakery::Associations.default_count = 3

      author = FactoryBakery.bake(author_model)

      expect(author.posts.size).to eq(3)
      expect(post_model.count).to eq(0)
    end

    it 'skips optional polymorphic belongs_to' do
      define_model('AllPolyTarget', name: :string)
      comment_model = define_model('AllPolyComment',
                                   notable_type: :string, notable_id: :integer) do
        belongs_to :notable, polymorphic: true, optional: true
      end

      comment = FactoryBakery.bake(comment_model)

      expect(comment.notable).to be_nil
      expect(comment.notable_id).to be_nil
      expect(comment.notable_type).to be_nil
    end

    it 'still raises for a required polymorphic belongs_to' do
      define_model('AllReqPolyTarget', name: :string)
      comment_model = define_model('AllReqPolyComment',
                                   notable_type: :string, notable_id: :integer) do
        belongs_to :notable, polymorphic: true, optional: false
      end

      expect { FactoryBakery.bake(comment_model) }.to raise_error(FactoryBakery::Error, /required polymorphic/)
    end

    it 'skips has_many :through and HABTM' do
      tag_model = define_model('AllSkipTag', name: :string)
      define_model('AllSkipTagging', post_id: :integer, tag_id: :integer) do
        belongs_to :post, class_name: 'AllSkipPost', optional: false
        belongs_to :tag, class_name: 'AllSkipTag', optional: false
      end
      create_table(:all_skip_posts_tags) do |table|
        table.integer :post_id
        table.integer :tag_id
      end
      post_model = define_model('AllSkipPost', title: :string) do
        has_many :taggings, class_name: 'AllSkipTagging', foreign_key: :post_id
        has_many :tags, through: :taggings, source: :tag, class_name: 'AllSkipTag'
        has_and_belongs_to_many :categories, class_name: 'AllSkipTag',
                                             join_table: :all_skip_posts_tags
      end

      post = FactoryBakery.bake(post_model)

      expect([post.tags, post.categories]).to all(be_empty)
      expect(tag_model.count).to eq(0)
    end
  end

  describe 'no back-edges' do
    it 'binds a collection child to its owner instead of building a second one' do
      author_model, = define_graph('AllBackOwner')

      author = FactoryBakery.bake(author_model)
      post = author.posts.first
      comment = post.comments.first

      expect(post.author).to equal(author)
      expect(comment.post).to equal(post)
      expect(comment.editor).to be_nil
    end

    it 'does not rebuild the child collection when a parent is built from a child' do
      _author, post_model, _comment = define_graph('AllBackParent')

      post = FactoryBakery.bake(post_model)

      expect(post.author).to be_a(Object.const_get('AllBackParentAuthor'))
      expect(post.author.posts).to be_empty
    end

    it 'persists exactly one row per node under bake!' do
      author_model, post_model, comment_model = define_graph('AllBangCounts')

      author = nil
      inserts = inserts_in { author = FactoryBakery.bake!(author_model) }

      expect([author_model.count, post_model.count, comment_model.count]).to eq([1, 1, 1])
      expect(author.posts.first.author_id).to eq(author.id)
      expect(inserts).to eq(3)
    end

    it 'persists one parent and no extra children when the root is a child' do
      _author, post_model, comment_model = define_graph('AllParentCounts')
      author_model = Object.const_get('AllParentCountsAuthor')

      FactoryBakery.bake!(post_model)

      expect([author_model.count, post_model.count, comment_model.count]).to eq([1, 1, 1])
    end
  end

  describe 'depth truncation' do
    it 'falls back to required-only building past max_depth' do
      author_model, = define_graph('AllDepth')
      FactoryBakery::Associations.max_depth = 2

      author = FactoryBakery.bake(author_model)
      comment = author.posts.first.comments.first

      expect(comment.post).to equal(author.posts.first)
      expect(comment.editor).to be_nil
    end

    it 'completes a four-level required chain past the depth budget under bake!' do
      define_model('AllFourL1', name: :string)
      define_model('AllFourL2', name: :string, l1_id: :integer, note: :string) do
        belongs_to :l1, class_name: 'AllFourL1', optional: false
        belongs_to :note_ref, class_name: 'AllFourNote', optional: true
      end
      define_model('AllFourNote', name: :string)
      define_model('AllFourL3', name: :string, l2_id: :integer) do
        belongs_to :l2, class_name: 'AllFourL2', optional: false
      end
      l4_model = define_model('AllFourL4', name: :string, l3_id: :integer) do
        belongs_to :l3, class_name: 'AllFourL3', optional: false
      end
      FactoryBakery::Associations.max_depth = 2

      leaf = FactoryBakery.bake!(l4_model)

      expect([Object.const_get('AllFourL1').count, Object.const_get('AllFourL2').count,
              Object.const_get('AllFourL3').count, l4_model.count]).to eq([1, 1, 1, 1])
      expect(leaf.l3.l2.l1).to be_persisted
      expect(leaf.l3.l2.note_ref).to be_nil
    end
  end

  describe 'configuration validation' do
    it 'accepts zero and positive integers for max_depth and default_count' do
      [0, 1, 5].each do |value|
        FactoryBakery::Associations.max_depth = value
        FactoryBakery::Associations.default_count = value
        expect(FactoryBakery::Associations.max_depth).to eq(value)
        expect(FactoryBakery::Associations.default_count).to eq(value)
      end
    end

    it 'rejects negative and non-integer max_depth and default_count' do
      [-1, 1.5, '3', nil].each do |value|
        expect { FactoryBakery::Associations.max_depth = value }
          .to raise_error(ArgumentError, /max_depth/)
        expect { FactoryBakery::Associations.default_count = value }
          .to raise_error(ArgumentError, /default_count/)
      end
    end
  end

  describe 'precedence, cycles and unchanged modes' do
    it 'lets a plain attribute block suppress a collection from auto-building' do
      author_model, = define_graph('AllDeclWins')
      FactoryBakery.define(author_model) { posts { [] } }

      author = FactoryBakery.bake(author_model)

      expect(author.posts).to eq([])
    end

    it 'lets x { nil } suppress a belongs_to from auto-building' do
      _author, post_model, = define_graph('AllNilWins')
      FactoryBakery.define(post_model) { author { nil } }

      expect(FactoryBakery.bake(post_model).author).to be_nil
    end

    it 'lets an association declaration suppress auto-building' do
      author_model, = define_graph('AllAssocWins')
      FactoryBakery.define(author_model) { association :posts, count: 0 }

      expect(FactoryBakery.bake(author_model).posts).to be_empty
    end

    it 'lets a call-site override suppress auto-building of both edges' do
      author_model, post_model, = define_graph('AllOverrideWins')
      author = author_model.create!(name: 'existing')

      post = FactoryBakery.bake(post_model, author: author)

      expect(post.author).to equal(author)
      expect(FactoryBakery.bake(author_model, posts: []).posts).to eq([])
    end

    it 'detects a required self-reference as a cycle' do
      node_model = define_model('AllSelfNode', name: :string, parent_id: :integer) do
        belongs_to :parent, class_name: 'AllSelfNode', optional: false
      end

      expect { FactoryBakery.bake(node_model) }
        .to raise_error(FactoryBakery::CyclicAssociationError, /AllSelfNode#parent -> AllSelfNode#parent/)
    end

    it 'detects a mutual required belongs_to cycle with the reflection path' do
      define_model('AllCycleAccount', owner_id: :integer)
      user_model = define_model('AllCycleUser', account_id: :integer) do
        belongs_to :account, class_name: 'AllCycleAccount', optional: false
      end
      Object.const_get('AllCycleAccount').belongs_to :owner, class_name: 'AllCycleUser', optional: false

      expect { FactoryBakery.bake(user_model) }
        .to raise_error(FactoryBakery::CyclicAssociationError, /AllCycleUser#account -> AllCycleAccount#owner/)
    end

    it 'leaves :required_only and :none unchanged' do
      _author, post_model, = define_graph('AllModes')

      FactoryBakery::Associations.mode = :required_only
      expect(FactoryBakery.bake(post_model).author).to be_nil

      FactoryBakery::Associations.mode = :none
      expect(FactoryBakery.bake(post_model).author).to be_nil
    end

    it 'keeps uniqueness across auto-built siblings' do
      author_model, = define_graph('AllUniqueness')
      comment_model = Object.const_get('AllUniquenessComment')
      comment_model.validates :body, uniqueness: true
      allow(FFaker::Lorem).to receive(:sentence).and_return(*(1..8).map { |index| "body-#{index}" })
      FactoryBakery::Associations.default_count = 2

      author = FactoryBakery.bake(author_model)
      bodies = author.posts.flat_map { |post| post.comments.map(&:body) }

      expect(bodies.size).to eq(4)
      expect(bodies.uniq.size).to eq(4)
    end

    it 'satisfies a presence-validated attribute on auto-built children' do
      user_model = define_model('AllPresenceUser', name: :string, active: { type: :boolean, default: false }) do
        validates :active, presence: true
      end
      define_model('AllPresenceProfile', bio: :string, user_id: :integer) do
        belongs_to :user, class_name: 'AllPresenceUser', optional: false
      end
      user_model.has_one :profile, class_name: 'AllPresenceProfile', inverse_of: :user

      user = FactoryBakery.bake(user_model)

      expect([user.active, user.profile.user]).to eq([true, user])
    end
  end
end
