# frozen_string_literal: true

require 'spec_helper'
require 'factory_bakery/associations'

# Discourse's `Post belongs_to :topic` is optional at the association level
# (`belongs_to_required_by_default` is false there), but `posts.topic_id` is
# NOT NULL and a custom validator (`validates_with PostValidator`) adds "Topic
# can't be blank". The lean attempt is invalid, the rebuild fills optional
# columns, but an optional belongs_to is never built, so the record stays
# invalid.
#
# The fix: the lean probe's error attribute names travel with the rebuild, and
# an optional belongs_to whose association name (or foreign key) is among them
# is built exactly as a required edge would be. Only the record being rebuilt
# is affected.
RSpec.describe 'error-directed optional belongs_to in the verified fallback' do
  before do
    FactoryBakery.reset_plugins!
    FactoryBakery.register_plugin(FactoryBakery::Associations::Plugin)
    FactoryBakery::Associations.mode = :required_only
  end

  after do
    FactoryBakery.reset_plugins!
    FactoryBakery::Associations.reset_configuration!
  end

  # `belongs_to_required_by_default` is true in a bare Rails app; Discourse
  # turns it off, so the edge is optional even though its column is not.
  def without_required_belongs_to_default
    previous = ActiveRecord::Base.belongs_to_required_by_default
    ActiveRecord::Base.belongs_to_required_by_default = false
    yield
  ensure
    ActiveRecord::Base.belongs_to_required_by_default = previous
  end

  it 'builds the optional belongs_to the lean probe blamed and bakes valid' do
    without_required_belongs_to_default do
      topic = define_model('ErrDirTopic', title: :string)
      post = define_model('ErrDirPost', body: :string, topic_id: { type: :integer, null: false }) do
        belongs_to :topic, class_name: 'ErrDirTopic', optional: true
      end
      post.validate { errors.add(:topic_id, :blank) if topic_id.nil? }

      record = FactoryBakery.bake!(post)

      expect(record).to be_persisted
      expect(record.topic).to be_persisted
      expect(record.topic_id).to eq(record.topic.id)
      expect(topic.count).to eq(1)
    end
  end

  it 'builds the blamed parent when a custom validator adds a plain-string blank message' do
    without_required_belongs_to_default do
      topic = define_model('ErrDirStringTopic', title: :string)
      post = define_model('ErrDirStringPost', body: :string, topic_id: { type: :integer, null: false }) do
        belongs_to :topic, class_name: 'ErrDirStringTopic', optional: true
      end
      post.validate { errors.add(:topic, "can't be blank") if topic.nil? }

      record = FactoryBakery.bake!(post)

      expect(record.topic).to be_persisted
      expect(topic.count).to eq(1)
    end
  end

  it 'still leaves an optional belongs_to alone when no validation demands it' do
    without_required_belongs_to_default do
      _topic, = define_model('ErrDirQuietTopic', title: :string)
      quiet = define_model('ErrDirQuietPost', body: :string, topic_id: :integer) do
        belongs_to :topic, class_name: 'ErrDirQuietTopic', optional: true
      end

      record = FactoryBakery.bake(quiet)

      expect(record.topic).to be_nil
      expect(record.topic_id).to be_nil
      expect(record).to be_valid
    end
  end

  it 'builds a parent when the error names the association rather than the foreign key' do
    without_required_belongs_to_default do
      topic = define_model('ErrDirNamedTopic', title: :string)
      post = define_model('ErrDirNamedPost', body: :string, topic_id: { type: :integer, null: false }) do
        belongs_to :topic, class_name: 'ErrDirNamedTopic', optional: true
      end
      post.validate { errors.add(:topic, :blank) if topic.nil? }

      record = FactoryBakery.bake!(post)

      expect(record).to be_persisted
      expect(record.topic).to be_a(topic)
      expect(record.topic).to be_persisted
    end
  end

  it 'persists the error-directed parent under bake!' do
    without_required_belongs_to_default do
      topic, = define_model('ErrDirBangTopic', title: :string)
      bang = define_model('ErrDirBangPost', body: :string, topic_id: { type: :integer, null: false }) do
        belongs_to :topic, class_name: 'ErrDirBangTopic', optional: true
      end
      bang.validate { errors.add(:topic_id, :blank) if topic_id.nil? }

      record = FactoryBakery.bake!(bang)

      expect(record).to be_persisted
      expect(record.topic).to be_persisted
      expect([topic.count, bang.count]).to eq([1, 1])
    end
  end

  it 'does not insert a parent when the foreign key error is invalid' do
    topic = define_model('ErrDirInvalidTopic', title: :string)
    post = define_model('ErrDirInvalidPost', body: :string, topic_id: :integer) do
      belongs_to :topic, class_name: 'ErrDirInvalidTopic', optional: true
      validate { errors.add(:topic_id, :invalid) if body.blank? }
    end

    record = FactoryBakery.bake(post)

    expect(record).to be_valid
    expect(record.topic).to be_nil
    expect(topic.count).to eq(0)
  end

  it 'does not build a parent for a nested bake the probe did not blame' do
    without_required_belongs_to_default do
      child_topic = define_model('ErrDirNestedTopic', title: :string)
      child = define_model('ErrDirNestedChild', body: :string, topic_id: { type: :integer, null: false }) do
        belongs_to :topic, class_name: 'ErrDirNestedTopic', optional: true
      end
      child.validate { errors.add(:topic_id, :blank) if topic_id.nil? }
      parent = define_model('ErrDirNestedParent', name: :string) do
        attr_accessor :child
      end
      FactoryBakery.define(parent) { child { FactoryBakery.bake(child) } }

      record = FactoryBakery.bake(parent)

      expect(record.child.topic).to be_a(child_topic)
    end
  end
end
