# frozen_string_literal: true

require 'spec_helper'
require 'active_support/notifications'
require 'factory_bakery/associations'

# W3 (issue #43): some apps validate the raw FK column (`validates :owner_id,
# presence: true`) instead of the association. An unsaved auto-built parent has
# a nil id, so its FK stays nil and validation fails. These examples exercise
# the public define/bake/bake! API only.
RSpec.describe 'raw-FK presence edges' do
  before do
    FactoryBakery.reset_plugins!
    FactoryBakery.register_plugin(FactoryBakery::Associations::Plugin)
    FactoryBakery::Associations.reset_configuration!
  end

  after do
    FactoryBakery.reset_plugins!
    FactoryBakery::Associations.reset_configuration!
  end

  def inserts_in
    count = 0
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |_name, _start, _finish, _id, payload|
      count += 1 if payload[:sql].match?(/\AINSERT/i)
    end
    yield
    count
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  # The edge's required signal is the FK COLUMN; the association is optional.
  def define_fk_edge(prefix, association_presence: false)
    owner = define_model("#{prefix}Owner", name: :string)
    child = define_model("#{prefix}Child", owner_id: :integer, name: :string) do
      belongs_to :owner, class_name: "#{prefix}Owner", optional: !association_presence
      validates :owner_id, presence: true
      validates :owner, presence: true if association_presence
    end
    [owner, child]
  end

  # The edge's required signal is ASSOCIATION presence only: today's semantics.
  def define_association_edge(prefix)
    owner = define_model("#{prefix}Owner", name: :string)
    child = define_model("#{prefix}Child", owner_id: :integer, name: :string) do
      belongs_to :owner, class_name: "#{prefix}Owner", optional: false
    end
    [owner, child]
  end

  describe 'bake!' do
    it 'persists a real parent, fills the FK and produces a valid record end-to-end' do
      owner_model, child_model = define_fk_edge('FkBang')

      child = FactoryBakery.bake!(child_model)

      expect(child).to be_valid
      expect(child.persisted?).to be(true)
      expect(child.owner.persisted?).to be(true)
      expect(child.owner_id).to eq(child.owner.id)
      expect(child_model.first.owner_id).to eq(child.owner.id)
      expect([owner_model.count, child_model.count]).to eq([1, 1])
    end

    it 'rolls the parent back atomically when the root save fails' do
      owner_model, child_model = define_fk_edge('FkBangRollback')
      child_model.validates :name, absence: true

      expect { FactoryBakery.bake!(child_model, name: 'invalid') }
        .to raise_error(ActiveRecord::RecordInvalid)

      expect([owner_model.count, child_model.count]).to eq([0, 0])
    end

    it 'persists the parent when both the FK column and the association are presence-validated' do
      _owner_model, child_model = define_fk_edge('FkBothSignals', association_presence: true)

      child = FactoryBakery.bake!(child_model)

      expect(child.owner).to be_persisted
      expect(child.owner_id).to eq(child.owner.id)
    end
  end

  describe 'bake unsaved-contract behavior' do
    it 'inserts the parent so the FK is real, documenting the row as an exception to the unsaved graph' do
      owner_model, child_model = define_fk_edge('FkBake')

      writes = inserts_in { @child = FactoryBakery.bake(child_model) }

      expect(@child).to be_valid
      expect(@child.owner).to be_persisted
      expect(@child.owner_id).to eq(@child.owner.id)
      expect(writes).to eq(1)
      expect(owner_model.count).to eq(1)
      expect(child_model.count).to eq(0)
    end

    it 'keeps association-presence edges unsaved with zero INSERTs' do
      owner_model, child_model = define_association_edge('AssocBake')

      writes = inserts_in { @child = FactoryBakery.bake(child_model) }

      expect(writes).to eq(0)
      expect(@child.owner).to be_new_record
      expect(@child.owner_id).to be_nil
      expect(owner_model.count).to eq(0)
    end
  end

  describe 'strategy interplay' do
    it 'reuses an existing row instead of creating another one under bake!' do
      owner_model, child_model = define_fk_edge('FkReuseHit')
      existing = owner_model.create!(name: 'existing')

      child = FactoryBakery::Associations.with(strategy: :reuse_non_unique) { FactoryBakery.bake!(child_model) }

      expect(child.owner).to eq(existing)
      expect(child.owner_id).to eq(existing.id)
      expect(owner_model.count).to eq(1)
    end

    it 'reuses an existing row for an explicit declaration' do
      owner_model, child_model = define_fk_edge('FkDeclReuse')
      existing = owner_model.create!(name: 'existing')
      FactoryBakery.define(child_model) { association :owner, strategy: :reuse_non_unique }

      child = FactoryBakery.bake(child_model)

      expect(child.owner).to eq(existing)
      expect(owner_model.count).to eq(1)
    end

    it 'shares an in-graph reused parent across two FK-presence paths without extra rows' do
      owner_model = define_model('FkDiamondOwner', name: :string)
      first = define_model('FkDiamondFirst', owner_id: :integer) do
        belongs_to :owner, class_name: 'FkDiamondOwner', optional: true
        validates :owner_id, presence: true
      end
      second = define_model('FkDiamondSecond', owner_id: :integer, first_id: :integer) do
        belongs_to :owner, class_name: 'FkDiamondOwner', optional: true
        belongs_to :first, class_name: 'FkDiamondFirst', optional: true
        validates :owner_id, presence: true
        validates :first_id, presence: true
      end
      existing = owner_model.create!(name: 'existing')
      FactoryBakery.define(first) { association :owner, strategy: :reuse_non_unique }
      FactoryBakery.define(second) do
        association :first
        association :owner, strategy: :reuse_non_unique
      end

      baked = FactoryBakery.bake(second)

      expect(baked.owner).to equal(baked.first.owner)
      expect([baked.owner_id, baked.first.owner_id]).to eq([existing.id, existing.id])
      expect(owner_model.count).to eq(1)
    end

    it 'falls back to a fresh, persisted parent on a reuse_non_unique miss under bake' do
      owner_model, child_model = define_fk_edge('FkReuseMiss')

      writes = inserts_in do
        @baked = FactoryBakery::Associations.with(strategy: :reuse_non_unique) { FactoryBakery.bake(child_model) }
      end

      expect(@baked.owner).to be_persisted
      expect(@baked.owner_id).to eq(@baked.owner.id)
      expect(writes).to eq(1)
      expect(owner_model.count).to eq(1)
      expect(child_model.count).to eq(0)
    end

    it 'falls back to a fresh, persisted parent for a declared edge on a reuse_non_unique miss under bake' do
      owner_model, child_model = define_fk_edge('FkDeclReuseMiss')
      FactoryBakery.define(child_model) { association :owner, strategy: :reuse_non_unique }

      child = FactoryBakery.bake(child_model)

      expect(child.owner).to be_persisted
      expect(child.owner_id).to eq(child.owner.id)
      expect(owner_model.count).to eq(1)
    end

    it 'creates the parent inside the savepoint on a reuse_non_unique miss under bake!' do
      owner_model, child_model = define_fk_edge('FkReuseMissBang')

      child = FactoryBakery::Associations.with(strategy: :reuse_non_unique) { FactoryBakery.bake!(child_model) }

      expect(child.owner).to be_persisted
      expect(owner_model.count).to eq(1)
    end

    it 'persists the parent for an explicit fresh declaration under bake!' do
      owner_model, child_model = define_fk_edge('FkDeclFresh')
      FactoryBakery.define(child_model) { association :owner, name: 'declared' }

      child = FactoryBakery.bake!(child_model)

      expect(child.owner.name).to eq('declared')
      expect(child.owner).to be_persisted
      expect(child.owner_id).to eq(child.owner.id)
      expect(owner_model.count).to eq(1)
    end
  end

  describe 'guards on the persisted-parent path' do
    it 'still raises CyclicAssociationError for a mutual FK-presence cycle without writing rows' do
      owner_model = define_model('FkCycleAlpha', beta_id: :integer) do
        belongs_to :beta, class_name: 'FkCycleBeta', optional: true
        validates :beta_id, presence: true
      end
      define_model('FkCycleBeta', alpha_id: :integer) do
        belongs_to :alpha, class_name: 'FkCycleAlpha', optional: true
        validates :alpha_id, presence: true
      end

      expect { FactoryBakery.bake(owner_model) }
        .to raise_error(
          FactoryBakery::CyclicAssociationError,
          /FkCycleAlpha#beta -> FkCycleBeta#alpha -> FkCycleAlpha#beta/
        )
      expect([owner_model.count, Object.const_get('FkCycleBeta').count]).to eq([0, 0])
    end

    it 'still enforces max_bake_depth on an FK-presence chain' do
      define_model('FkDepthC', name: :string)
      define_model('FkDepthB', c_id: :integer) do
        belongs_to :c, class_name: 'FkDepthC', optional: true
        validates :c_id, presence: true
      end
      child_model = define_model('FkDepthA', b_id: :integer) do
        belongs_to :b, class_name: 'FkDepthB', optional: true
        validates :b_id, presence: true
      end

      previous = FactoryBakery.max_bake_depth
      FactoryBakery.max_bake_depth = 2
      expect { FactoryBakery.bake(child_model) }
        .to raise_error(FactoryBakery::NestingTooDeepError, /max_bake_depth \(2\)/)
    ensure
      FactoryBakery.max_bake_depth = previous
    end

    it 'still suppresses the back edge in :all mode so no extra children are built' do
      owner_model = define_model('FkBackOwner', name: :string)
      child_model = define_model('FkBackChild', owner_id: :integer) do
        belongs_to :owner, class_name: 'FkBackOwner', optional: true
        validates :owner_id, presence: true
      end
      owner_model.class_eval do
        has_many :children, class_name: 'FkBackChild', foreign_key: :owner_id, inverse_of: :owner
      end
      FactoryBakery::Associations.mode = :all

      child = FactoryBakery.bake!(child_model)

      expect(child_model.count).to eq(1)
      expect(owner_model.count).to eq(1)
      expect(child.owner_id).to eq(child.owner.id)
    end

    # The FK-presence parent is valid itself, but its own required parent is
    # not; inserting it would let autosave skip that grandparent and write a
    # nil foreign key. The gem names the broken grandparent instead.
    it 'refuses to insert a parent whose required grandparent is invalid' do
      define_model('FkBrokenGrand', name: :string) do
        validate { errors.add(:base, 'needs app knowledge') }
      end
      define_model('FkBrokenParent', grand_id: :integer) do
        belongs_to :grand, class_name: 'FkBrokenGrand', optional: false
      end
      child_model = define_model('FkBrokenChild', parent_id: :integer) do
        belongs_to :parent, class_name: 'FkBrokenParent', optional: true
        validates :parent_id, presence: true
      end

      expect { FactoryBakery.bake(child_model) }
        .to raise_error(FactoryBakery::Error, /FkBrokenParent cannot be inserted: its required FkBrokenGrand/)
      expect(Object.const_get('FkBrokenParent').where(grand_id: nil).count).to eq(0)
    end
  end

  describe 'precedence and boundaries' do
    it 'lets an explicit FK override suppress the persisted-parent path' do
      owner_model, child_model = define_fk_edge('FkOverride')
      existing = owner_model.create!(name: 'existing')

      writes = inserts_in { @child = FactoryBakery.bake(child_model, owner_id: existing.id) }

      expect(writes).to eq(0)
      expect(@child.owner_id).to eq(existing.id)
      expect(owner_model.count).to eq(1)
    end

    it 'leaves :none mode unchanged' do
      owner_model, child_model = define_fk_edge('FkNone')
      FactoryBakery::Associations.mode = :none

      child = FactoryBakery.bake(child_model)

      expect(child.owner).to be_nil
      expect(child).not_to be_valid
      expect(owner_model.count).to eq(0)
    end

    it 'leaves polymorphic edges unchanged' do
      define_model('FkPolyPost', title: :string)
      comment_model = define_model('FkPolyComment', commentable_id: :integer, commentable_type: :string) do
        belongs_to :commentable, polymorphic: true, optional: true
        validates :commentable_id, presence: true
      end

      comment = FactoryBakery.bake(comment_model)

      expect(comment.commentable).to be_nil
      expect(comment.commentable_id).to be_nil
    end
  end
end
