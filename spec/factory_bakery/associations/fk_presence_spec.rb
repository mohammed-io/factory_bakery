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
  def define_fk_edge(prefix, association_presence: false, owner_columns: {}, child_columns: {})
    owner = define_model("#{prefix}Owner", name: :string, **owner_columns)
    child = define_model("#{prefix}Child", owner_id: :integer, name: :string, **child_columns) do
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

  describe 'shared-primary-key parents' do
    let(:models) do
      account = define_model('FkCallbackAccount', name: :string) do
        has_one :profile, class_name: 'FkCallbackProfile', inverse_of: :account
      end
      profile = define_model('FkCallbackProfile', account_id: :bigint, bio: :string) do
        self.primary_key = :account_id
        belongs_to :account, class_name: 'FkCallbackAccount', inverse_of: :profile, optional: false
      end
      profile.connection.add_index(profile.table_name, :account_id, unique: true)
      view = define_model('FkCallbackView', profile_id: :integer) do
        belongs_to :profile, class_name: 'FkCallbackProfile', optional: false
        validates :profile_id, presence: true
      end
      [account, profile, view]
    end

    def add_profile_callback(account)
      account.after_create do
        FkCallbackProfile.create!(account_id: id, bio: 'from callback')
      end
    end

    it 'uses the shared-primary-key parent created by a newly baked owner callback' do
      account, profile, view = models
      add_profile_callback(account)
      record = FactoryBakery.bake!(view).reload

      expect(record.profile.bio).to eq('from callback')
      expect(record.profile_id).to eq(account.sole.id)
      expect(profile.count).to eq(1)
    end

    it 'inserts the generated parent when the owner callback creates no row' do
      account, profile, view = models
      FactoryBakery.define(profile) { bio { 'from definition' } }
      record = FactoryBakery.bake!(view).reload

      expect(record.profile.bio).to eq('from definition')
      expect(record.profile_id).to eq(account.sole.id)
      expect(profile.count).to eq(1)
    end

    it 'preserves a generated inverse required by owner validation before save' do
      account, profile, view = models
      account.reflect_on_association(:profile).options[:autosave] = false
      account.validate { errors.add(:profile, :blank) unless profile }
      profile.class_eval do
        def account=(owner)
          super
          owner.association(:profile).target = self
          owner.association(:profile).loaded!
        end
      end

      record = FactoryBakery.bake!(view).reload

      expect(record.profile_id).to eq(account.sole.id)
      expect(profile.count).to eq(1)
    end

    it 'persists deferred children on the callback-created parent that is returned' do
      account, profile, view = models
      badge = define_model('FkCallbackBadge', profile_id: :integer) do
        belongs_to :profile, class_name: 'FkCallbackProfile', optional: false
      end
      profile.has_one :badge, class_name: 'FkCallbackBadge', foreign_key: :profile_id, inverse_of: :profile
      add_profile_callback(account)

      record = FactoryBakery::Associations.with(mode: :all) { FactoryBakery.bake!(view, fill_optional: true) }

      expect(record.profile.badge).to be_persisted
      expect(badge.pluck(:profile_id)).to eq([record.profile_id])
    end

    it 'does not adopt a same-class row with a different key through a scoped inverse' do
      account, profile, view = models
      account.has_one :profile, -> { unscope(where: :account_id).where(bio: 'other').order(:account_id) },
                      class_name: 'FkCallbackProfile', inverse_of: :account
      profile.insert_all!([{ account_id: 100, bio: 'other' }])
      FactoryBakery.define(profile) { bio { 'generated' } }

      record = FactoryBakery.bake!(view).reload

      expect(record.profile_id).to eq(account.sole.id)
      expect(record.profile.bio).to eq('generated')
    end

    it 'rolls the owner and its callback-created parent back when saving the root fails', :savepoints do
      account, profile, view = models
      add_profile_callback(account)
      view.validate { errors.add(:base, 'cannot save view') }

      expect { FactoryBakery.bake!(view) }.to raise_error(ActiveRecord::RecordInvalid, /cannot save view/)
      expect([account.count, profile.count, view.count]).to eq([0, 0, 0])
    end
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

    it 'rolls the parent back atomically when the root save fails', :savepoints do
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

  describe 'optional has_one children of an owner the gem saves' do
    # The owner is saved to give the FK-presence child a real id. Its optional
    # has_one stat is built automatically under plain bake, so autosave must not
    # insert it alongside the owner's own callback row.
    def define_stat_graph(prefix, callback:, stat_columns: {}, stat_scope: nil, stat_options: {}, **edge_options)
      stat_model = define_model("#{prefix}Stat", owner_id: :integer, label: :string, **stat_columns) do
        belongs_to :owner, class_name: "#{prefix}Owner", optional: false
      end
      stat_model.connection.add_index(stat_model.table_name, :owner_id, unique: true)
      owner_model, child_model = define_fk_edge(prefix, **edge_options)
      owner_model.has_one :stat, stat_scope, class_name: "#{prefix}Stat", inverse_of: :owner, **stat_options
      owner_model.after_create { create_stat!(label: 'from callback') } if callback
      [owner_model, child_model, stat_model]
    end

    it 'keeps only the stat created by the owner callback under plain bake' do
      _owner_model, child_model, stat_model = define_stat_graph('FkStatCallback', callback: true)

      child = FactoryBakery::Associations.with(mode: :all) { FactoryBakery.bake(child_model) }

      expect(child.owner).to be_persisted
      expect(child.owner.stat.label).to eq('from callback')
      expect(stat_model.pluck(:owner_id)).to eq([child.owner.id])
    end

    it 'assigns the automatically built stat to the saved owner when no callback creates one' do
      _owner_model, child_model, stat_model = define_stat_graph('FkStatPlain', callback: false)

      child = FactoryBakery::Associations.with(mode: :all) { FactoryBakery.bake(child_model) }

      expect(child.owner).to be_persisted
      expect(child.owner.stat).to be_a(stat_model)
      expect(child.owner.stat.owner).to equal(child.owner)
      expect(stat_model.count).to eq(0)
    end

    def define_discarded_stat_graph(explicit:, required:)
      profile = define_model('FkDiscardProfile', name: :string)
      owner, child, stat = define_stat_graph(
        'FkDiscard',
        callback: true,
        stat_columns: { profile_id: :integer },
        owner_columns: { backup_id: :integer },
        child_columns: { profile_id: :integer }
      )
      stat.belongs_to :profile, class_name: 'FkDiscardProfile', optional: true, autosave: false
      owner.belongs_to :backup, class_name: 'FkDiscardProfile', optional: true, autosave: false
      owner.attr_reader :generated_stat
      owner.validates :stat, presence: true, unless: :generated_stat if required
      owner.define_method(:stat=) do |value|
        @generated_stat = value
        self.backup = value.profile unless explicit
        super(value)
      end
      FactoryBakery.define(owner) { skip :backup }
      FactoryBakery.define(stat) { association :profile } if explicit
      [owner, child, profile]
    end

    [true, false].each do |explicit|
      descendant = explicit ? 'a definition-built descendant' : 'the shared parent'

      it "still shares #{descendant} after plain bake discards an automatic child" do
        _owner, child, _profile = define_discarded_stat_graph(explicit: explicit, required: false)
        child.belongs_to :profile, class_name: 'FkDiscardProfile', optional: false

        record = FactoryBakery::Associations.with(mode: :all, max_depth: 5) { FactoryBakery.bake(child) }

        expect(record.owner.stat.label).to eq('from callback')
        expect(record.profile).to equal(record.owner.generated_stat.profile)
      end

      it "still verifies #{descendant} after bake! discards an automatic child", :savepoints do
        owner, child, _profile = define_discarded_stat_graph(explicit: explicit, required: true)

        expect do
          FactoryBakery::Associations.with(mode: :all, max_depth: 5) { FactoryBakery.bake!(child) }
        end.to raise_error(FactoryBakery::IncompletePersistenceError, /FkDiscardProfile/)
        expect(owner.count).to eq(0)
      end
    end

    it 'leaves an autosave-disabled child attached while saving its owner' do
      owner, child, stat = define_stat_graph('FkDisabledStat', callback: false, stat_options: { autosave: false })
      observed = nil
      owner.before_create { observed = self.stat }

      record = FactoryBakery::Associations.with(mode: :all) { FactoryBakery.bake(child) }

      expect(observed).to be_a(stat)
      expect(record.owner.stat).to equal(observed)
      expect(stat.count).to eq(0)
    end

    it 'keeps the generated child when reload finds a different STI class' do
      owner, child, stat = define_stat_graph('FkTypedStat', callback: false, stat_columns: { type: :string })
      alternate = define_class('FkAlternateStat', stat)
      owner.after_create { alternate.create!(owner_id: id, label: 'from callback') }

      record = FactoryBakery::Associations.with(mode: :all) { FactoryBakery.bake(child) }

      expect(record.owner.stat).to be_an_instance_of(stat)
      expect(record.owner.stat).to be_new_record
      expect(alternate.count).to eq(1)
    end

    it 'keeps the generated child when a scope returns a row with a different owner key' do
      scope = -> { unscope(where: :owner_id).where(label: 'unrelated') }
      _owner, child, stat = define_stat_graph('FkWrongKeyStat', callback: false, stat_scope: scope)
      stat.insert_all!([{ owner_id: 100, label: 'unrelated' }])

      record = FactoryBakery::Associations.with(mode: :all) { FactoryBakery.bake(child) }

      expect(record.owner.stat).to be_new_record
      expect(record.owner.stat.owner).to equal(record.owner)
      expect(stat.pluck(:owner_id)).to eq([100])
    end

    it 'restores the generated child when the post-save association lookup raises' do
      scope = ->(record) { raise 'stat lookup failed' if record.persisted? }
      owner, child, stat = define_stat_graph('FkRestoreStat', callback: false, stat_scope: scope)
      attempted_owner = nil
      owner.before_create { attempted_owner = self }

      expect do
        FactoryBakery::Associations.with(mode: :all) { FactoryBakery.bake(child) }
      end.to raise_error('stat lookup failed')
      expect(attempted_owner.stat).to be_a(stat)
      expect(owner.count).to eq(0)
    end

    it 'leaves descendants attached inside a detached subtree' do
      owner, child, stat = define_stat_graph('FkPrunedStat', callback: true)
      metric = define_model('FkPrunedMetric', stat_id: :integer) do
        belongs_to :stat, class_name: 'FkPrunedStatStat', optional: false
      end
      stat.has_one :metric, class_name: metric.name, inverse_of: :stat
      generated_stat = nil
      observed_metric = nil
      owner.define_method(:stat=) do |value|
        generated_stat = value
        super(value)
      end
      owner.after_create { observed_metric = generated_stat.metric }

      record = FactoryBakery::Associations.with(mode: :all, max_depth: 5) { FactoryBakery.bake(child) }

      expect(record.owner.stat).to be_persisted
      expect(observed_metric).to be_a(metric)
      expect(metric.count).to eq(0)
    end

    it 'settles children of a changed persisted parent reached through autosave' do
      parent, dependent, stat = define_stat_graph('FkChangedStat', callback: false)
      parent.after_update { stat.create!(owner_id: id, label: 'from update') }
      owner, child = define_fk_edge('FkChangedOuter', owner_columns: { parent_id: :integer })
      owner.belongs_to :parent, class_name: parent.name, autosave: true, optional: false
      FactoryBakery.define(owner) do
        parent do
          FactoryBakery.bake(dependent).owner.tap { |record| record.name = 'updated' }
        end
      end

      record = FactoryBakery::Associations.with(mode: :all, max_depth: 6) { FactoryBakery.bake(child) }

      expect(record.owner.parent.reload.name).to eq('updated')
      expect(stat.where(owner_id: record.owner.parent_id).pluck(:label)).to eq(['from update'])
    end

    # Saving the owner also autosaves its new optional belongs_to parent. That
    # parent's own callback-created has_one must win over the gem's stat too
    # (Discourse: saving a Topic autosaves its unsaved `deleted_by` User).
    it 'keeps the callback stat of a new parent that the owner save autosaves' do
      stat_model = define_model('FkDeepStat', user_id: :integer, label: :string) do
        belongs_to :user, class_name: 'FkDeepUser', optional: false
      end
      stat_model.connection.add_index(stat_model.table_name, :user_id, unique: true)
      define_model('FkDeepUser', name: :string) do
        has_one :stat, class_name: 'FkDeepStat', foreign_key: :user_id, inverse_of: :user
        # A direct insert, like Discourse's UserStat.create!(user_id: id): the
        # has_one writer would quietly unlink an existing row instead.
        after_create { FkDeepStat.create!(user_id: id, label: 'from callback') }
      end
      define_model('FkDeepOwner', name: :string, deleter_id: :integer) do
        belongs_to :deleter, class_name: 'FkDeepUser', optional: true
      end
      child_model = define_model('FkDeepChild', owner_id: :integer) do
        belongs_to :owner, class_name: 'FkDeepOwner', optional: true
        validates :owner_id, presence: true
      end

      # Child > Owner > Deleter > Stat: deep enough that :all builds the stat.
      child = FactoryBakery::Associations.with(mode: :all, max_depth: 5) { FactoryBakery.bake(child_model) }

      deleter = child.owner.deleter
      expect(deleter).to be_persisted
      expect(stat_model.where(user_id: deleter.id).pluck(:label)).to eq(['from callback'])
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
      FactoryBakery.define(child_model) { association :owner, with: { name: 'declared' } }

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
