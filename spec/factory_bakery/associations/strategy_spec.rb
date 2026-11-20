# frozen_string_literal: true

require 'spec_helper'
require 'factory_bakery/associations'

# Public-API behavior for A15: strategy: :fresh | :reuse_non_unique. Every assertion goes
# through define/bake/bake! or the plugin's public configuration API.
RSpec.describe 'association strategies' do
  before do
    FactoryBakery.reset_plugins!
    FactoryBakery.register_plugin(FactoryBakery::Associations::Plugin)
    FactoryBakery::Associations.reset_configuration!
  end

  after do
    FactoryBakery.reset_plugins!
    FactoryBakery::Associations.reset_configuration!
  end

  def define_category_and_post(prefix = 'Strateg', category_columns: { name: :string, active: :boolean })
    category = define_model("#{prefix}Category", **category_columns)
    post = define_model("#{prefix}Post", category_id: :integer) do
      belongs_to :category, class_name: "#{prefix}Category", optional: false
    end
    [category, post]
  end

  def insert_count
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, _start, _finish, _id, payload|
      count += 1 if payload[:sql].match?(/\AINSERT/i)
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  describe 'database lookup' do
    it 'reuses the oldest matching row and inserts no category under bake!' do
      category, post = define_category_and_post('StrategOldest')
      oldest = category.create!(name: 'News')
      category.create!(name: 'Sport')
      FactoryBakery.define(post) { association :category, strategy: :reuse_non_unique }

      baked = FactoryBakery.bake!(post)

      expect(baked.category).to eq(oldest)
      expect(category.count).to eq(2)
    end

    it 'reuses an existing row under bake without writing anything' do
      category, post = define_category_and_post('StrategBakeHit')
      existing = category.create!(name: 'News')
      FactoryBakery.define(post) { association :category, strategy: :reuse_non_unique }

      writes = insert_count { @baked = FactoryBakery.bake(post) }

      expect(@baked.category).to eq(existing)
      expect(writes).to eq(0)
    end

    it 'matches scalar column overrides passed to the association' do
      category, post = define_category_and_post('StrategMatch')
      category.create!(name: 'News')
      sport = category.create!(name: 'Sport')
      FactoryBakery.define(post) { association :category, strategy: :reuse_non_unique, name: 'Sport' }

      expect(FactoryBakery.bake(post).category).to eq(sport)
    end

    it 'builds fresh when an override is not a column' do
      category, post = define_category_and_post('StrategNonColumn')
      existing = category.create!(name: 'News')
      FactoryBakery.define(post) { association :category, strategy: :reuse_non_unique, bogus: 'x' }

      baked = FactoryBakery.bake(post)

      expect(baked.category).not_to eq(existing)
      expect(baked.category).to be_new_record
      expect(category.count).to eq(1)
    end

    it 'builds fresh when an override is not a scalar' do
      category, post = define_category_and_post('StrategNonScalar')
      existing = category.create!(name: 'News')
      FactoryBakery.define(post) { association :category, strategy: :reuse_non_unique, name: ['News'] }

      baked = FactoryBakery.bake(post)

      expect(baked.category).not_to eq(existing)
      expect(category.count).to eq(1)
    end

    it 'honors the association scope on the lookup' do
      category, = define_category_and_post('StrategScope')
      scoped_post = define_model('StrategScopeScopedPost', category_id: :integer) do
        belongs_to :category, -> { where(active: true) },
                   class_name: 'StrategScopeCategory', optional: false
      end
      category.create!(name: 'Hidden', active: false)
      active = category.create!(name: 'Shown', active: true)
      FactoryBakery.define(scoped_post) { association :category, strategy: :reuse_non_unique }

      expect(FactoryBakery.bake(scoped_post).category).to eq(active)
    end

    it 'restricts an STI subclass lookup to its own class' do
      base = define_model('StrategVehicle', name: :string, type: :string)
      car = define_class('StrategCar', base)
      define_class('StrategTruck', base)
      post = define_model('StrategVehiclePost', vehicle_id: :integer) do
        belongs_to :vehicle, class_name: 'StrategVehicle', optional: false
      end
      truck = base.create!(name: 'truck', type: 'StrategTruck')
      expected_car = base.create!(name: 'car', type: 'StrategCar')
      FactoryBakery.define(post) { association :vehicle, factory: car, strategy: :reuse_non_unique }

      expect(FactoryBakery.bake(post).vehicle).to eq(expected_car)
      expect(truck.name).to eq('truck')
    end

    it 'does not pick a sibling subclass for a base-class lookup' do
      base = define_model('StrategBaseVehicle', name: :string, type: :string)
      define_class('StrategBaseTruck', base)
      post = define_model('StrategBaseVehiclePost', vehicle_id: :integer) do
        belongs_to :vehicle, class_name: 'StrategBaseVehicle', optional: false
      end
      base.create!(name: 'truck', type: 'StrategBaseTruck')
      FactoryBakery.define(post) { association :vehicle, strategy: :reuse_non_unique }

      expect(FactoryBakery.bake(post).vehicle).to be_new_record
    end

    it 'uses factory: to name the table for a polymorphic belongs_to' do
      post = define_model('StrategPolyPost', title: :string)
      comment = define_model(
        'StrategPolyComment', body: :string, commentable_type: :string, commentable_id: :integer
      ) do
        belongs_to :commentable, polymorphic: true, optional: false
      end
      existing = post.create!(title: 'chosen')
      FactoryBakery.define(comment) { association :commentable, factory: post, strategy: :reuse_non_unique }

      baked = FactoryBakery.bake(comment)

      expect(baked.commentable).to eq(existing)
      expect(baked.commentable_type).to eq(post.polymorphic_name)
    end

    it 'reorders by primary key so a default scope order does not win' do
      category, post = define_category_and_post('StrategReorder')
      oldest = category.create!(name: 'News')
      category.create!(name: 'Sport')
      category.class_eval { default_scope { order(name: :desc) } }
      FactoryBakery.define(post) { association :category, strategy: :reuse_non_unique }

      expect(FactoryBakery.bake(post).category).to eq(oldest)
    end

    it 'raises for a model without a primary key' do
      define_model('StrategNoPk', name: :string) { self.primary_key = nil }
      post = define_model('StrategNoPkPost', target_id: :integer) do
        belongs_to :target, class_name: 'StrategNoPk', optional: false
      end
      FactoryBakery.define(post) { association :target, strategy: :reuse_non_unique }

      expect { FactoryBakery.bake(post) }.to raise_error(ArgumentError, /primary key/)
    end

    it 'raises for a model with a composite primary key' do
      define_model('StrategComposite', name: :string) { self.primary_key = %i[region code] }
      post = define_model('StrategCompositePost', target_region: :integer, target_code: :integer) do
        belongs_to :target, class_name: 'StrategComposite',
                            foreign_key: %i[target_region target_code], optional: false
      end
      FactoryBakery.define(post) { association :target, strategy: :reuse_non_unique }

      expect { FactoryBakery.bake(post) }.to raise_error(ArgumentError, /primary key/)
    end
  end

  describe 'uniqueness rule' do
    it 'builds a fresh parent when the foreign key has a unique index' do
      category, post = define_category_and_post('ReuseUniqueIndex')
      post.connection.add_index(post.table_name, :category_id, unique: true)
      existing = category.create!(name: 'News')
      FactoryBakery.define(post) { association :category, strategy: :reuse_non_unique }

      first = FactoryBakery.bake!(post)
      second = FactoryBakery.bake!(post)

      expect(first.category).not_to eq(existing)
      expect(second.category).not_to eq(first.category)
      expect(first).to be_persisted
      expect(second).to be_persisted
    end

    it 'builds a fresh parent when a composite unique index includes the foreign key' do
      category = define_model('ReuseCompositeCategory', name: :string)
      post = define_model('ReuseCompositePost', category_id: :integer, slot: :integer) do
        belongs_to :category, class_name: 'ReuseCompositeCategory', optional: false
      end
      post.connection.add_index(post.table_name, %i[category_id slot], unique: true)
      category.create!(name: 'News')
      FactoryBakery.define(post) { association :category, strategy: :reuse_non_unique }

      first = FactoryBakery.bake(post)
      second = FactoryBakery.bake(post)

      expect(first.category).not_to eq(second.category)
      expect(first.category).to be_new_record
      expect(second.category).to be_new_record
    end

    it 'builds a fresh parent when the foreign key is uniqueness-validated' do
      category, post = define_category_and_post('ReuseUniqueValidator')
      post.class_eval { validates :category_id, uniqueness: true }
      existing = category.create!(name: 'News')
      FactoryBakery.define(post) { association :category, strategy: :reuse_non_unique }

      first = FactoryBakery.bake!(post)
      second = FactoryBakery.bake!(post)

      expect(first.category).not_to eq(existing)
      expect(second.category).not_to eq(first.category)
      expect(first).to be_persisted
      expect(second).to be_persisted
    end

    it 'builds a fresh parent when the inverse association is a has_one' do
      author = define_model('ReuseOneAuthor', name: :string)
      profile = define_model('ReuseOneProfile', author_id: :integer) do
        belongs_to :author, class_name: 'ReuseOneAuthor', inverse_of: :profile, optional: false
      end
      author.class_eval do
        has_one :profile, class_name: 'ReuseOneProfile', inverse_of: :author
      end
      existing_author = author.create!(name: 'Existing')
      profile.create!(author: existing_author)
      FactoryBakery.define(profile) { association :author, strategy: :reuse_non_unique }

      first = FactoryBakery.bake!(profile)
      second = FactoryBakery.bake!(profile)

      expect(first.author).not_to eq(existing_author)
      expect(second.author).not_to eq(first.author)
      expect(first).to be_persisted
      expect(second).to be_persisted
    end
  end

  describe 'miss behavior' do
    it 'builds an unsaved target and inserts nothing under bake' do
      category, post = define_category_and_post('StrategMissBake')
      FactoryBakery.define(post) { association :category, strategy: :reuse_non_unique }

      writes = insert_count { @baked = FactoryBakery.bake(post) }

      expect(@baked.category).to be_new_record
      expect(writes).to eq(0)
      expect(category.count).to eq(0)
    end

    it 'persists the fresh target under bake! and reuses it afterwards' do
      category, post = define_category_and_post('StrategMissBang')
      FactoryBakery.define(post) { association :category, strategy: :reuse_non_unique }

      first = FactoryBakery.bake!(post)
      second = FactoryBakery.bake!(post)

      expect(first.category).to be_persisted
      expect(category.count).to eq(1)
      expect(second.category).to eq(first.category)
    end

    it 'applies a named factory only on a miss' do
      category, post = define_category_and_post('StrategNamedMiss')
      FactoryBakery.define(:strateg_named_category, klass: category) { name { 'from factory' } }
      FactoryBakery.define(post) do
        association :category, factory: :strateg_named_category, strategy: :reuse_non_unique
      end

      expect(FactoryBakery.bake(post).category.name).to eq('from factory')

      category.create!(name: 'existing')
      expect(FactoryBakery.bake(post).category.name).to eq('existing')
    end
  end

  describe 'in-graph sharing' do
    def define_diamond(prefix)
      author = define_model("#{prefix}Author", name: :string)
      article = define_model("#{prefix}Article", author_id: :integer) do
        belongs_to :author, class_name: "#{prefix}Author", optional: false
      end
      review = define_model("#{prefix}Review", author_id: :integer, article_id: :integer) do
        belongs_to :author, class_name: "#{prefix}Author", optional: false
        belongs_to :article, class_name: "#{prefix}Article", optional: false
      end
      FactoryBakery.define(article) { association :author, strategy: :reuse_non_unique }
      FactoryBakery.define(review) do
        association :article
        association :author, strategy: :reuse_non_unique
      end
      [author, review]
    end

    it 'shares one freshly built parent across two paths in the same graph' do
      _author, review = define_diamond('StrategFreshDiamond')

      baked = FactoryBakery.bake(review)

      expect(baked.author).to equal(baked.article.author)
    end

    it 'shares one database row across two paths in the same graph' do
      author, review = define_diamond('StrategDbDiamond')
      author.create!(name: 'shared')

      baked = FactoryBakery.bake(review)

      expect(baked.author).to equal(baked.article.author)
      expect(author.count).to eq(1)
    end

    it 'does not share an in-graph object whose overrides do not match' do
      define_model('StrategMismatchPerson', name: :string)
      post = define_model('StrategMismatchPost', author_id: :integer, editor_id: :integer) do
        belongs_to :author, class_name: 'StrategMismatchPerson', optional: false
        belongs_to :editor, class_name: 'StrategMismatchPerson', optional: false
      end
      FactoryBakery.define(post) do
        association :author, strategy: :reuse_non_unique, name: 'Author'
        association :editor, strategy: :reuse_non_unique, name: 'Editor'
      end

      baked = FactoryBakery.bake(post)

      expect([baked.author.name, baked.editor.name]).to eq(%w[Author Editor])
      expect(baked.author).not_to equal(baked.editor)
    end

    it 'starts with an empty graph for a separate top-level bake' do
      _author, review = define_diamond('StrategFreshTop')
      first = FactoryBakery.bake(review)
      second = FactoryBakery.bake(review)

      expect(second.author).not_to equal(first.author)
    end
  end

  describe 'validation' do
    it 'rejects the old :reuse strategy name' do
      expect { FactoryBakery::Associations.strategy = :reuse }
        .to raise_error(ArgumentError, /invalid associations strategy :reuse/)
      FactoryBakery.define(Object) { association :x, strategy: :reuse }
      expect { FactoryBakery.bake(Object) }
        .to raise_error(ArgumentError, /invalid associations strategy :reuse/)
    end

    it 'rejects an explicit reuse_non_unique strategy on has_many' do
      author = define_model('StrategCollAuthor', name: :string)
      define_model('StrategCollPost', author_id: :integer) do
        belongs_to :author, class_name: 'StrategCollAuthor', optional: false
      end
      author.class_eval do
        has_many :posts, class_name: 'StrategCollPost', inverse_of: :author
      end
      FactoryBakery.define(author) { association :posts, strategy: :reuse_non_unique }

      expect { FactoryBakery.bake(author) }
        .to raise_error(ArgumentError, /only supported on belongs_to/)
    end

    it 'rejects an explicit reuse_non_unique strategy on has_one' do
      author = define_model('StrategOneAuthor', name: :string)
      define_model('StrategOneProfile', author_id: :integer) do
        belongs_to :author, class_name: 'StrategOneAuthor', optional: false
      end
      author.class_eval do
        has_one :profile, class_name: 'StrategOneProfile', inverse_of: :author
      end
      FactoryBakery.define(author) { association :profile, strategy: :reuse_non_unique }

      expect { FactoryBakery.bake(author) }
        .to raise_error(ArgumentError, /only supported on belongs_to/)
    end

    it 'silently ignores an inherited reuse_non_unique strategy on collections' do
      author = define_model('StrategInheritedAuthor', name: :string)
      post = define_model('StrategInheritedPost', author_id: :integer) do
        belongs_to :author, class_name: 'StrategInheritedAuthor', optional: false
      end
      author.class_eval do
        has_many :posts, class_name: 'StrategInheritedPost', inverse_of: :author
      end
      FactoryBakery.define(author) { association :posts, count: 2 }

      baked = FactoryBakery::Associations.with(strategy: :reuse_non_unique) { FactoryBakery.bake!(author) }

      expect(baked.posts.size).to eq(2)
      expect(post.count).to eq(2)
    end

    it 'rejects traits combined with reuse_non_unique' do
      category, post = define_category_and_post('StrategTraits')
      FactoryBakery.define(category) { trait(:special) { name { 'special' } } }
      FactoryBakery.define(post) { association :category, :special, strategy: :reuse_non_unique }

      expect { FactoryBakery.bake(post) }
        .to raise_error(ArgumentError, /traits cannot be combined with strategy: :reuse_non_unique/)
    end

    it 'rejects an encrypted attribute override with reuse_non_unique' do
      ActiveRecord::Encryption.configure(
        primary_key: 'a' * 32, deterministic_key: 'b' * 32, key_derivation_salt: 'c' * 32
      )
      category, post = define_category_and_post(
        'StrategEncrypted', category_columns: { name: :string, secret: :string }
      )
      category.class_eval { encrypts :secret }
      FactoryBakery.define(post) { association :category, strategy: :reuse_non_unique, secret: 'abc' }

      expect { FactoryBakery.bake(post) }.to raise_error(ArgumentError, /encrypted/)
    end

    it 'rejects a serialized column override with reuse_non_unique' do
      category, post = define_category_and_post(
        'StrategSerialized', category_columns: { name: :string, settings: :text }
      )
      category.class_eval { serialize :settings }
      FactoryBakery.define(post) { association :category, strategy: :reuse_non_unique, settings: { 'x' => 1 } }

      expect { FactoryBakery.bake(post) }.to raise_error(ArgumentError, /serialized/)
    end
  end

  describe 'precedence' do
    it 'defaults to :fresh' do
      category, post = define_category_and_post('StrategDefault')
      existing = category.create!(name: 'News')
      FactoryBakery.define(post) { association :category }

      expect(FactoryBakery::Associations.strategy).to eq(:fresh)
      expect(FactoryBakery.bake(post).category).not_to eq(existing)
    end

    it 'lets a per-association strategy beat a scoped strategy' do
      category, post = define_category_and_post('StrategPerWins')
      existing = category.create!(name: 'News')
      FactoryBakery.define(post) { association :category, strategy: :fresh }

      FactoryBakery::Associations.with(strategy: :reuse_non_unique) do
        expect(FactoryBakery.bake(post).category).not_to eq(existing)
      end
    end

    it 'lets a scoped strategy beat the global strategy' do
      category, post = define_category_and_post('StrategScopedWins')
      existing = category.create!(name: 'News')
      FactoryBakery.define(post) { association :category }
      FactoryBakery::Associations.strategy = :fresh

      FactoryBakery::Associations.with(strategy: :reuse_non_unique) do
        expect(FactoryBakery.bake(post).category).to eq(existing)
      end
      expect(FactoryBakery.bake(post).category).not_to eq(existing)
    end

    it 'applies a global strategy to declarations without one' do
      category, post = define_category_and_post('StrategGlobal')
      existing = category.create!(name: 'News')
      FactoryBakery.define(post) { association :category }
      FactoryBakery::Associations.strategy = :reuse_non_unique

      expect(FactoryBakery.bake(post).category).to eq(existing)
    end

    it 'applies a scoped reuse_non_unique strategy to an auto-built required belongs_to' do
      account = define_model('StrategAutoAccount', name: :string)
      user = define_model('StrategAutoUser', account_id: :integer) do
        belongs_to :account, class_name: 'StrategAutoAccount', optional: false
      end
      existing = account.create!(name: 'x')

      baked = FactoryBakery::Associations.with(strategy: :reuse_non_unique) { FactoryBakery.bake!(user) }

      expect(baked.account).to eq(existing)
      expect(account.count).to eq(1)
    end

    it 'restores the previous strategy when the scope raises' do
      category, post = define_category_and_post('StrategRestore')
      existing = category.create!(name: 'News')
      FactoryBakery.define(post) { association :category }

      expect do
        FactoryBakery::Associations.with(strategy: :reuse_non_unique) { raise 'boom' }
      end.to raise_error(RuntimeError, 'boom')

      expect(FactoryBakery::Associations.strategy).to eq(:fresh)
      expect(FactoryBakery.bake(post).category).not_to eq(existing)
    end

    it 'validates strategy values and accepts a scoped strategy' do
      expect { FactoryBakery::Associations.strategy = :sometimes }
        .to raise_error(ArgumentError, /sometimes/)
      expect { FactoryBakery::Associations.with(strategy: :sometimes) {} }
        .to raise_error(ArgumentError, /strategy/)
      FactoryBakery.define(Object) { association :x, strategy: :sometimes }
      expect { FactoryBakery.bake(Object) }.to raise_error(ArgumentError, /sometimes/)
      expect(FactoryBakery::Associations.with(strategy: :reuse_non_unique) { FactoryBakery::Associations.strategy })
        .to eq(:reuse_non_unique)
    end
  end
end
