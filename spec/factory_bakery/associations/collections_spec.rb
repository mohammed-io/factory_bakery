# frozen_string_literal: true

require 'spec_helper'
require 'active_support/notifications'
require 'factory_bakery/associations'

# Public-API behavior for A12: explicit collections and has_one built through
# the association, with count:, owner blocks and inverse/scope binding. Every
# assertion goes through define/bake/bake!, row counts, SQL notifications or
# ActiveRecord's public association API -- never builder internals.
RSpec.describe 'FactoryBakery association collections and has_one (A12)' do
  before do
    FactoryBakery.reset_plugins!
    FactoryBakery.register_plugin(FactoryBakery::Associations::Plugin)
    FactoryBakery::Associations.mode = :required_only
  end

  after do
    FactoryBakery.reset_plugins!
    FactoryBakery::Associations.reset_configuration!
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

  # Post has_many :comments; Comment belongs_to :post, optional: false.
  # Rails auto-detects the inverse in this shape.
  def define_post_and_comment(prefix)
    comment = define_model("#{prefix}Comment", body: :string, post_id: :integer) do
      belongs_to :post, class_name: "#{prefix}Post", optional: false
    end
    post = define_model("#{prefix}Post", title: :string) do
      has_many :comments, class_name: "#{prefix}Comment", inverse_of: :post
    end
    [post, comment]
  end

  describe 'count: on has_many' do
    it 'builds N distinct children bound to the owner, with no database writes under bake' do
      post_model, comment_model = define_post_and_comment('CollCount')
      FactoryBakery.define(post_model) { association :comments, count: 3, with: { body: 'nice' } }

      post = nil
      inserts = inserts_in { post = FactoryBakery.bake(post_model) }

      expect(inserts).to eq(0)
      expect(post.comments.size).to eq(3)
      expect(post.comments.map(&:object_id).uniq.size).to eq(3)
      expect(post.comments.map(&:body).uniq).to eq(['nice'])
      expect(post.comments.all? { |comment| comment.post.equal?(post) }).to be(true)
      expect([post_model.count, comment_model.count]).to eq([0, 0])
    end

    it 'persists exactly one owner and N children under bake! through autosave' do
      post_model, comment_model = define_post_and_comment('CollBang')
      FactoryBakery.define(post_model) { association :comments, count: 3 }

      post = FactoryBakery.bake!(post_model)

      expect([post_model.count, comment_model.count]).to eq([1, 3])
      expect(post.comments.all?(&:persisted?)).to be(true)
      expect(post.comments.all? { |comment| comment.post_id == post.id }).to be(true)
      expect(post.comments.all? { |comment| comment.post.equal?(post) }).to be(true)
    end

    it 'defaults to one child when count: is omitted' do
      post_model, _comment_model = define_post_and_comment('CollDefault')
      FactoryBakery.define(post_model) { association :comments }

      expect(FactoryBakery.bake(post_model).comments.size).to eq(1)
    end

    it 'builds an empty, loaded collection for count: 0' do
      post_model, comment_model = define_post_and_comment('CollZero')
      FactoryBakery.define(post_model) { association :comments, count: 0 }

      post = FactoryBakery.bake(post_model)

      expect(post.comments.size).to eq(0)
      expect(post.association(:comments)).to be_loaded
      expect(comment_model.count).to eq(0)
    end

    it 'applies overrides to every child' do
      post_model, _comment_model = define_post_and_comment('CollOverride')
      FactoryBakery.define(post_model) { association :comments, count: 2, with: { body: 'same' } }

      expect(FactoryBakery.bake(post_model).comments.map(&:body)).to eq(%w[same same])
    end

    it 'lets each child keep uniqueness enforcement on a heuristic attribute' do
      post_model, comment_model = define_post_and_comment('CollUnique')
      comment_model.validates :body, uniqueness: true
      FactoryBakery.define(post_model) { association :comments, count: 3 }
      # Issue #59 moved body values to a paragraph heuristic; stub that
      # boundary so the three children collide and force regeneration.
      allow_any_instance_of(FactoryBakery::AttributeFillers::StringFiller)
        .to receive(:generate_paragraph).and_return('alpha', 'beta', 'gamma')

      post = FactoryBakery.bake(post_model, title: 'given', fill_optional: true)

      expect(post.comments.map(&:body)).to eq(%w[alpha beta gamma])
      expect(post.comments.map(&:body).uniq.size).to eq(3)
    end
  end

  describe 'association scope and inverse binding' do
    it 'applies scope attributes to children without building a stray parent' do
      comment_model = define_model(
        'CollScopedComment', body: :string, visible: :boolean,
                             post_id: { type: :integer, null: false }
      ) do
        belongs_to :post, class_name: 'CollScopedPost', optional: true
      end
      post_model = define_model('CollScopedPost', title: :string) do
        has_many :visible_comments, -> { where(visible: true) },
                 class_name: 'CollScopedComment', foreign_key: :post_id
      end
      FactoryBakery.define(post_model) { association :visible_comments, count: 2 }

      post = FactoryBakery.bake!(post_model)

      expect(post.visible_comments.map(&:visible)).to eq([true, true])
      expect([post_model.count, comment_model.count]).to eq([1, 2])
      expect(post.visible_comments.all? { |comment| comment.post_id == post.id }).to be(true)
    end

    it 'sets a consistent type and id on polymorphic as: children' do
      post_model = define_model('CollPolyPost', title: :string) do
        has_many :notes, as: :notable, class_name: 'CollPolyNote'
      end
      note_model = define_model(
        'CollPolyNote', body: :string, notable_type: :string, notable_id: :integer
      ) do
        belongs_to :notable, polymorphic: true, optional: false
      end
      FactoryBakery.define(post_model) { association :notes, count: 1 }

      post = FactoryBakery.bake!(post_model)
      note = post.notes.first

      expect([note.notable_type, note.notable_id == note.notable.id]).to eq([post_model.polymorphic_name, true])
      expect(note.notable).to equal(post)
      expect([post_model.count, note_model.count]).to eq([1, 1])
    end

    it 'does not build a second parent for an association without a verified inverse' do
      comment_model = define_model(
        'CollNoInverseComment', body: :string, post_id: { type: :integer, null: false }
      ) do
        belongs_to :post, class_name: 'CollNoInversePost', optional: true
      end
      post_model = define_model('CollNoInversePost', title: :string) do
        has_many :loose_comments, class_name: 'CollNoInverseComment', foreign_key: :post_id, inverse_of: false
      end
      FactoryBakery.define(post_model) { association :loose_comments, count: 2 }

      post = FactoryBakery.bake!(post_model)

      expect([post_model.count, comment_model.count]).to eq([1, 2])
      expect(post.loose_comments.all? { |comment| comment.post_id == post.id }).to be(true)
    end
  end

  describe 'has_one' do
    it 'builds exactly one child bound to the owner' do
      profile_model = define_model('CollProfile', bio: :string, user_id: :integer) do
        belongs_to :user, class_name: 'CollHasOneUser', optional: false
      end
      user_model = define_model('CollHasOneUser', name: :string) do
        has_one :profile, class_name: 'CollProfile', inverse_of: :user
      end
      FactoryBakery.define(user_model) { association :profile }

      user = FactoryBakery.bake(user_model)

      expect(user.profile).to be_a(profile_model)
      expect(user.profile.user).to equal(user)
      expect([user_model.count, profile_model.count]).to eq([0, 0])
    end

    it 'persists the child after the owner under bake!' do
      profile_model = define_model('CollBangProfile', bio: :string, user_id: :integer) do
        belongs_to :user, class_name: 'CollBangUser', optional: false
      end
      user_model = define_model('CollBangUser', name: :string) do
        has_one :profile, class_name: 'CollBangProfile', inverse_of: :user
      end
      FactoryBakery.define(user_model) { association :profile }

      user = FactoryBakery.bake!(user_model)

      expect([user_model.count, profile_model.count]).to eq([1, 1])
      expect(user.profile.user_id).to eq(user.id)
    end

    it 'rejects count: on a has_one association' do
      _profile_model = define_model('CollProfileCount', bio: :string, user_id: :integer) do
        belongs_to :user, class_name: 'CollUserCount', optional: false
      end
      user_model = define_model('CollUserCount', name: :string) do
        has_one :profile, class_name: 'CollProfileCount', inverse_of: :user
      end
      FactoryBakery.define(user_model) { association :profile, count: 2 }

      expect { FactoryBakery.bake(user_model) }
        .to raise_error(ArgumentError, /count:.*collection/)
    end
  end

  describe 'owner blocks' do
    it 'receives the owner after all plain attributes are applied' do
      team_model = define_model('CollBlockTeam', name: :string)
      user_model = define_model('CollBlockUser', name: :string, team_id: :integer) do
        belongs_to :team, class_name: 'CollBlockTeam', optional: true
      end
      post_model = define_model('CollBlockPost', title: :string, team_id: :integer, reviewer_id: :integer) do
        belongs_to :reviewer, class_name: 'CollBlockUser', optional: true
        belongs_to :team, class_name: 'CollBlockTeam', optional: true
      end
      FactoryBakery.define(post_model) do
        team { FactoryBakery.bake(team_model) }
        association(:reviewer) { |post| FactoryBakery.bake(user_model, team: post.team) }
      end

      post = FactoryBakery.bake(post_model)

      expect(post.team).to be_a(team_model)
      expect(post.reviewer.team).to equal(post.team)
    end

    it 'assigns an Array returned by a collection block' do
      post_model, comment_model = define_post_and_comment('CollBlockArray')
      FactoryBakery.define(post_model) do
        association(:comments) { |owner| [FactoryBakery.bake(comment_model, body: owner.title, post: owner)] }
      end

      post = FactoryBakery.bake(post_model, title: 'from-owner')

      expect(post.comments.map(&:body)).to eq(['from-owner'])
    end

    it 'rejects a block combined with count:, traits or overrides' do
      post_model, _comment_model = define_post_and_comment('CollBlockConflict')
      cases = [
        proc { association(:comments, count: 2) { |_owner| [] } },
        proc { association(:comments, :some_trait) { |_owner| [] } },
        proc { association(:comments, with: { body: 'x' }) { |_owner| [] } }
      ]

      cases.each do |declaration|
        FactoryBakery.define(post_model, &declaration)
        expect { FactoryBakery.bake(post_model) }.to raise_error(ArgumentError, /block/)
      end
    end
  end

  describe 'count: validation' do
    it 'rejects a negative or non-integer count' do
      post_model, _comment_model = define_post_and_comment('CollBadCount')

      [-1, 1.5, '3'].each do |bad_count|
        FactoryBakery.define(post_model) { association :comments, count: bad_count }
        expect { FactoryBakery.bake(post_model) }
          .to raise_error(ArgumentError, /count:.*non-negative Integer/)
      end
    end

    it 'rejects count: on a belongs_to association' do
      comment_model = define_model('CollSingularCountComment', post_id: :integer) do
        belongs_to :post, class_name: 'CollSingularCountPost', optional: false
      end
      define_model('CollSingularCountPost', title: :string)
      FactoryBakery.define(comment_model) { association :post, count: 2 }

      expect { FactoryBakery.bake(comment_model) }
        .to raise_error(ArgumentError, /count:.*collection/)
    end
  end

  describe 'unsupported association shapes' do
    it 'rejects has_many :through via association but keeps attribute blocks working' do
      tag_model = define_model('CollThroughTag', name: :string)
      define_model('CollThroughTagging', post_id: :integer, tag_id: :integer) do
        belongs_to :post, class_name: 'CollThroughPost', optional: false
        belongs_to :tag, class_name: 'CollThroughTag', optional: false
      end
      post_model = define_model('CollThroughPost', title: :string) do
        has_many :taggings, class_name: 'CollThroughTagging', foreign_key: :post_id
        has_many :tags, through: :taggings, source: :tag, class_name: 'CollThroughTag'
      end
      FactoryBakery.define(post_model) { association :tags }

      expect { FactoryBakery.bake(post_model) }
        .to raise_error(FactoryBakery::Error, /not supported; assign via an attribute block/)

      FactoryBakery.define(post_model) { tags { [FactoryBakery.bake(tag_model)] } }
      expect(FactoryBakery.bake(post_model).tags.size).to eq(1)
    end

    it 'rejects has_and_belongs_to_many via association' do
      define_model('CollHABTMCategory', name: :string)
      create_table(:coll_h_a_b_t_m_posts_categories) do |table|
        table.integer :post_id
        table.integer :category_id
      end
      post_model = define_model('CollHABTMPost', title: :string) do
        has_and_belongs_to_many :categories,
                                class_name: 'CollHABTMCategory',
                                join_table: :coll_h_a_b_t_m_posts_categories
      end
      FactoryBakery.define(post_model) { association :categories }

      expect { FactoryBakery.bake(post_model) }
        .to raise_error(FactoryBakery::Error, /not supported; assign via an attribute block/)
    end
  end

  describe 'callbacks, persistence and depth' do
    it 'surfaces an error raised by a before_add callback' do
      define_model('CollCallbackComment', body: :string, post_id: :integer) do
        belongs_to :post, class_name: 'CollCallbackPost', optional: false
      end
      post_model = define_model('CollCallbackPost', title: :string) do
        has_many :comments, class_name: 'CollCallbackComment', foreign_key: :post_id,
                            before_add: ->(_owner, _child) { raise 'boom from before_add' }
      end
      FactoryBakery.define(post_model) { association :comments, count: 1 }

      expect { FactoryBakery.bake(post_model) }
        .to raise_error(RuntimeError, /boom from before_add/)
    end

    it 'raises the persistence-contract error for an autosave: false collection and leaves no rows' do
      comment_model = define_model('CollNoAutosaveComment', body: :string, post_id: :integer) do
        belongs_to :post, class_name: 'CollNoAutosavePost', optional: false
      end
      post_model = define_model('CollNoAutosavePost', title: :string) do
        has_many :comments, class_name: 'CollNoAutosaveComment', foreign_key: :post_id,
                            inverse_of: :post, autosave: false
      end
      FactoryBakery.define(post_model) { association :comments, count: 2 }

      expect { FactoryBakery.bake!(post_model) }
        .to raise_error(FactoryBakery::IncompletePersistenceError, /comments/)
      expect([post_model.count, comment_model.count]).to eq([0, 0])
    end

    it 'applies the depth backstop to collection children' do
      post_model, _comment_model = define_post_and_comment('CollDepth')
      FactoryBakery.define(post_model) { association :comments, count: 1 }
      previous = FactoryBakery.max_bake_depth
      FactoryBakery.max_bake_depth = 1

      expect { FactoryBakery.bake(post_model) }
        .to raise_error(FactoryBakery::NestingTooDeepError, /max_bake_depth/)
    ensure
      FactoryBakery.max_bake_depth = previous
    end
  end
end
