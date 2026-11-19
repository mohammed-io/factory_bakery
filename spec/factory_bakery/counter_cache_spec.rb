# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'counter-cache columns' do
  include DefineConstantMacros

  # The counter-cache option lives on the child's belongs_to; the parent must
  # declare the matching has_many for Rails to expose the counter metadata.
  def define_post(columns)
    define_model('Post', columns) do
      has_many :comments
    end
  end

  def define_comment(**options)
    define_model('Comment', post_id: :integer) do
      belongs_to :post, **options, optional: false
    end
  end

  describe 'a standard counter cache' do
    before do
      define_post(title: :string, comments_count: :integer)
      define_comment(counter_cache: true)
    end

    it 'never invents a value for a nullable counter column' do
      records = Array.new(3) { FactoryBakery.bake(Post) }

      expect(records.map(&:comments_count)).to all(be_nil)
    end

    it 'uses zero for a NOT NULL counter column without a default' do
      define_post(comments_count: { type: :integer, null: false })
      define_comment(counter_cache: true)

      expect(FactoryBakery.bake(Post).comments_count).to eq(0)
    end

    it 'preserves a database default on the counter column' do
      define_post(comments_count: { type: :integer, default: 7 })
      define_comment(counter_cache: true)

      expect(FactoryBakery.bake(Post).comments_count).to eq(7)
    end

    it 'still fills non-counter columns on the same model heuristically' do
      record = FactoryBakery.bake(Post, fill_optional: true)

      expect(record.comments_count).to be_nil
      expect(record.title).to be_a(String)
      expect(record.title).not_to be_empty
    end

    it 'keeps declarations and call-site overrides working on the counter column' do
      FactoryBakery.define(Post) { comments_count { 99 } }

      expect(FactoryBakery.bake(Post).comments_count).to eq(99)
      expect(FactoryBakery.bake(Post, comments_count: 42).comments_count).to eq(42)
    end

    it 'persists a baked parent with a NOT NULL counter column' do
      define_post(comments_count: { type: :integer, null: false })
      define_comment(counter_cache: true)

      record = FactoryBakery.bake!(Post)

      expect(record).to be_persisted
      expect(record.reload.comments_count).to eq(0)
    end
  end

  describe 'a custom-named counter cache' do
    before do
      define_post(unusual_tally: :integer)
    end

    it 'is left nil when declared on the child without inverse_of' do
      define_comment(counter_cache: :unusual_tally)

      expect(FactoryBakery.bake(Post).unusual_tally).to be_nil
    end

    it 'is left nil when declared on the child with inverse_of' do
      define_comment(counter_cache: :unusual_tally, inverse_of: :comments)

      expect(FactoryBakery.bake(Post).unusual_tally).to be_nil
    end

    it 'uses zero for a NOT NULL custom counter column' do
      define_post(unusual_tally: { type: :integer, null: false })
      define_comment(counter_cache: :unusual_tally)

      expect(FactoryBakery.bake(Post).unusual_tally).to eq(0)
    end
  end

  describe 'a plain column ending in _count' do
    it 'is still filled heuristically when it is not a counter cache' do
      define_model('Survey', answer_count: :integer)

      value = FactoryBakery.bake(Survey, fill_optional: true).answer_count

      expect(value).to be_a(Integer)
    end
  end

  describe 'unusual association shapes' do
    it 'does not break baking a model with a has_many :through' do
      define_model('Article', title: :string) do
        has_many :taggings
        has_many :tags, through: :taggings
      end
      define_model('Tagging', article_id: :integer, tag_id: :integer) do
        belongs_to :article, optional: false
        belongs_to :tag, optional: false
      end
      define_model('Tag', name: :string)

      record = FactoryBakery.bake(Article, fill_optional: true)

      expect(record.title).to be_a(String)
    end
  end
end
