# frozen_string_literal: true

require 'spec_helper'
require 'factory_bakery/associations'

# A18: the guard-rails and the associations plugin were designed around real
# database constraints. These examples run unchanged on SQLite (with FK
# enforcement on), PostgreSQL and MySQL; the connection comes from
# DATABASE_URL, and in-memory SQLite is the default.
RSpec.describe 'real database constraints across adapters' do
  include DefineConstantMacros

  before do
    FactoryBakery.reset_plugins!
    FactoryBakery.register_plugin(FactoryBakery::Associations::Plugin)
    FactoryBakery::Associations.mode = :required_only
  end

  after do
    FactoryBakery.reset_plugins!
    FactoryBakery::Associations.reset_configuration!
  end

  describe 'the test connection' do
    it 'uses the adapter selected by DATABASE_URL' do
      actual = case ActiveRecord::Base.connection.adapter_name.downcase
               when /sqlite/ then 'sqlite3'
               when /postgres/ then 'postgresql'
               when /mysql/ then 'mysql2'
               end

      expect(DatabaseSupport.adapter).to eq(actual)
    end

    it 'enforces foreign keys, so the nil-FK guard-rail is not vacuous' do
      create_table(:fk_probe_parents) { |t| t.string :name }
      create_table(:fk_probe_children) do |t|
        t.references :fk_probe_parent, foreign_key: true
      end

      expect do
        ActiveRecord::Base.connection.execute(
          'INSERT INTO fk_probe_children (fk_probe_parent_id) VALUES (987654)'
        )
      end.to raise_error(ActiveRecord::InvalidForeignKey)
    end
  end

  describe 'an optional belongs_to backed by a real FK' do
    let!(:parent_model) do
      create_table(:constraint_parents) { |t| t.string :name }
      define_class('ConstraintParent', ActiveRecord::Base)
    end

    let!(:child_model) do
      create_table(:constraint_children) do |t|
        t.references :constraint_parent, foreign_key: true
        t.string :name
      end
      define_class('ConstraintChild', ActiveRecord::Base) do
        belongs_to :constraint_parent, class_name: 'ConstraintParent', optional: true
      end
    end

    it 'leaves the FK nil under bake and never writes a dangling FK under bake!' do
      expect(FactoryBakery.bake(child_model).constraint_parent_id).to be_nil

      record = FactoryBakery.bake!(child_model)

      expect(record.constraint_parent_id).to be_nil
      expect(child_model.count).to eq(1)
      expect(child_model.first.constraint_parent_id).to be_nil
    end
  end

  describe 'a required belongs_to with NOT NULL and a real FK' do
    let!(:parent_model) do
      create_table(:guard_parents) { |t| t.string :name }
      define_class('GuardParent', ActiveRecord::Base)
    end

    let!(:child_model) do
      create_table(:guard_children) do |t|
        t.references :guard_parent, null: false, foreign_key: true
        t.string :name
      end
      define_class('GuardChild', ActiveRecord::Base) do
        belongs_to :guard_parent, class_name: 'GuardParent', optional: false
      end
    end

    it 'auto-builds the parent unsaved under bake' do
      child = FactoryBakery.bake(child_model)

      expect(child.guard_parent).to be_a(parent_model)
      expect(child.guard_parent).to be_new_record
      expect(child.guard_parent_id).to be_nil
    end

    it 'inserts the parent first and satisfies NOT NULL and the FK under bake!' do
      child = FactoryBakery.bake!(child_model)

      expect(child.reload.guard_parent_id).to eq(child.guard_parent.id)
      expect(parent_model.count).to eq(1)
      expect(child_model.count).to eq(1)
      expect(child.guard_parent_id).not_to be_nil
    end
  end

  # W3: NOT NULL is required at the database level, but a presence validator on
  # the raw FK column is a *model-level* requirement checked before autosave
  # can fill it. Only a persisted parent gives the column a real value.
  describe 'a raw-FK presence validator backed by NOT NULL and a real FK' do
    let!(:parent_model) do
      create_table(:fk_presence_owners) { |t| t.string :name }
      define_class('FkPresenceOwner', ActiveRecord::Base)
    end

    let!(:child_model) do
      create_table(:fk_presence_children) do |t|
        t.references :fk_presence_owner, null: false, foreign_key: true
        t.string :name
      end
      define_class('FkPresenceChild', ActiveRecord::Base) do
        belongs_to :fk_presence_owner, class_name: 'FkPresenceOwner', optional: true
        validates :fk_presence_owner_id, presence: true
      end
    end

    it 'satisfies both constraints under bake! with the parent inserted first' do
      child = FactoryBakery.bake!(child_model)

      expect(child).to be_valid
      expect(child.reload.fk_presence_owner_id).to eq(child.fk_presence_owner.id)
      expect([parent_model.count, child_model.count]).to eq([1, 1])
    end

    it 'inserts the parent under bake so the FK is real' do
      child = FactoryBakery.bake(child_model)

      expect(child).to be_valid
      expect(child.fk_presence_owner).to be_persisted
      expect(child.fk_presence_owner_id).to eq(child.fk_presence_owner.id)
      expect(parent_model.count).to eq(1)
      expect(child_model.count).to eq(0)
    end
  end

  describe 'a counter cache on a NOT NULL column with a real FK' do
    let!(:parent_model) do
      create_table(:guard_posts) do |t|
        t.string :title
        t.integer :guard_comments_count, null: false
      end
      define_class('GuardPost', ActiveRecord::Base) do
        has_many :guard_comments, class_name: 'GuardComment', foreign_key: :guard_post_id
      end
    end

    let!(:child_model) do
      create_table(:guard_comments) do |t|
        t.references :guard_post, null: false, foreign_key: true
        t.string :body
      end
      define_class('GuardComment', ActiveRecord::Base) do
        belongs_to :guard_post, class_name: 'GuardPost', optional: false,
                                counter_cache: :guard_comments_count
      end
    end

    it 'uses zero instead of a random count and keeps the FK valid under bake!' do
      built = FactoryBakery.bake(child_model)
      expect(built.guard_post.guard_comments_count).to eq(0)

      comment = FactoryBakery.bake!(child_model)

      expect(comment.reload.guard_post_id).to eq(comment.guard_post.id)
      expect(comment.guard_post.reload.guard_comments_count).to eq(1)
    end
  end

  describe 'other guard-rails on adapter-appropriate column types' do
    it 'preserves the STI type so the saved subclass loads back' do
      create_table(:guard_vehicles) do |t|
        t.string :type
        t.string :name
      end
      vehicle_model = define_class('GuardVehicle', ActiveRecord::Base)
      car_model = define_class('GuardCar', vehicle_model)

      record = FactoryBakery.bake!(car_model)

      expect(record.type).to eq('GuardCar')
      expect(vehicle_model.find(record.id)).to be_a(car_model)
    end

    it 'leaves a polymorphic type/id pair nil instead of inventing a constant' do
      create_table(:guard_events) do |t|
        t.references :guard_eventable, polymorphic: true
        t.string :name
      end
      event_model = define_class('GuardEvent', ActiveRecord::Base) do
        belongs_to :guard_eventable, polymorphic: true, optional: true
      end

      record = FactoryBakery.bake(event_model)
      expect([record.guard_eventable_type, record.guard_eventable_id]).to eq([nil, nil])

      expect { FactoryBakery.bake!(event_model) }.not_to raise_error
      expect(event_model.count).to eq(1)
    end

    it 'round-trips a JSON value using the column type the adapter supports' do
      create_table(:guard_documents) do |t|
        t.string :title
        t.column :payload, DatabaseSupport.json_type
        DatabaseSupport.add_array_column(t, :tags)
      end
      document_model = define_class('GuardDocument', ActiveRecord::Base)

      record = FactoryBakery.bake!(document_model)
      reloaded = document_model.find(record.id)

      expect(reloaded.payload).to be_a(Hash)
      expect(reloaded.payload).to eq(record.payload)
    end
  end
end
