# frozen_string_literal: true

require 'spec_helper'
require 'securerandom'
require 'factory_bakery/associations'

# The database's foreign key constraints name the table a belongs_to row points
# at. That answers two questions the class names cannot: which parent a
# belongs_to with no constant should build, and which candidate a polymorphic
# belongs_to must pick so the constraint holds.
#
# Every model and table carries a per-example prefix. Discovery reads every loaded
# ActiveRecord class, so names reused across examples would make a model look
# ambiguous.
RSpec.describe 'belongs_to targets named by a foreign key constraint' do
  let(:prefix) { "Fk#{SecureRandom.hex(3)}" }

  before do
    FactoryBakery.reset_plugins!
    FactoryBakery.register_plugin(FactoryBakery::Associations::Plugin)
    FactoryBakery::Associations.mode = :required_only
    FactoryBakery::Associations.eager_load = false
    FactoryBakery::ActiveRecordMapper::PolymorphicTargetDiscovery.reset!
    DatabaseSupport.enable_foreign_keys!
  end

  after do
    FactoryBakery.reset_plugins!
    FactoryBakery::Associations.reset_configuration!
    FactoryBakery::ActiveRecordMapper::PolymorphicTargetDiscovery.reset!
  end

  describe 'a belongs_to whose class name has no constant' do
    let!(:parent_model) { define_model("#{prefix}Parent", name: :string) }

    # A child whose `ghost` edge names a constant that does not exist. `real_id`
    # is constrained to the parent table when `constrained`.
    def define_ghost_child(label, column:, constrained:)
      table = "#{prefix.downcase}_#{label}_children"
      parent_table = parent_model.table_name
      create_table(table) do |t|
        if constrained
          t.references column, foreign_key: { to_table: parent_table }
        else
          t.integer "#{column}_id"
        end
      end
      define_class("#{prefix}#{label.capitalize}Child", ActiveRecord::Base) do
        belongs_to :ghost, class_name: 'MissingConst', foreign_key: :"#{column}_id", optional: true
      end
    end

    def declare_ghost(model)
      FactoryBakery.define(model) { association :ghost }
    end

    it 'bakes the parent that the foreign key constraint names' do
      child = define_ghost_child('constrained', column: :real, constrained: true)
      declare_ghost(child)

      record = FactoryBakery.bake!(child)

      expect(parent_model.count).to eq(1)
      expect(record.real_id).to eq(parent_model.first.id)
    end

    it 'surfaces the original error when no foreign key constraint covers the column' do
      child = define_ghost_child('plain', column: :plain, constrained: false)
      declare_ghost(child)

      expect { FactoryBakery.bake(child) }.to raise_error(FactoryBakery::Error, /MissingConst/)
    end

    it 'surfaces the original error when two loaded models store the referenced table' do
      parent_table = parent_model.table_name
      define_class("#{prefix}Twin", ActiveRecord::Base) { self.table_name = parent_table }
      child = define_ghost_child('twin', column: :real, constrained: true)
      declare_ghost(child)

      expect { FactoryBakery.bake(child) }.to raise_error(FactoryBakery::Error, /MissingConst/)
    end

    it 'ignores an STI subclass of the referenced model' do
      define_class("#{prefix}Sub", parent_model)
      child = define_ghost_child('sti', column: :real, constrained: true)
      declare_ghost(child)

      record = FactoryBakery.bake!(child)

      expect(record.real_id).to eq(parent_model.first.id)
    end

    it 'surfaces the original error when the referenced table has no loaded model' do
      orphan_table = "#{prefix.downcase}_orphans"
      create_table(orphan_table) { |t| t.string :label }
      create_table("#{prefix.downcase}_orphan_children") do |t|
        t.references :orphan, foreign_key: { to_table: orphan_table }
      end
      orphan_child = define_class("#{prefix}OrphanChild", ActiveRecord::Base) do
        belongs_to :ghost, class_name: 'MissingConst', foreign_key: :orphan_id, optional: true
      end
      declare_ghost(orphan_child)

      expect { FactoryBakery.bake(orphan_child) }.to raise_error(FactoryBakery::Error, /MissingConst/)
    end

    it 'surfaces the original error when the adapter cannot list foreign keys' do
      child = define_ghost_child('unlisted', column: :real, constrained: true)
      declare_ghost(child)
      allow(ActiveRecord::Base.connection).to receive(:foreign_keys).and_raise(NotImplementedError)

      expect { FactoryBakery.bake(child) }.to raise_error(FactoryBakery::Error, /MissingConst/)
    end
  end

  describe 'a polymorphic belongs_to whose id column has a foreign key constraint' do
    let!(:user_model) { define_model("#{prefix}User", name: :string) }
    let!(:account_model) { define_model("#{prefix}Account", name: :string) }

    # An application whose polymorphic owner is stored in `owner_id`. Each class
    # in `owners` declares the `as: :owner` inverse that makes it a candidate.
    # When `constrained`, owner_id carries a foreign key to the user table.
    def define_application(label, owners:, constrained:)
      name = "#{prefix}#{label}Application"
      table = "#{prefix.downcase}_#{label.downcase}_applications"
      user_table = user_model.table_name
      create_table(table) do |t|
        t.string :owner_type
        t.integer :owner_id
        t.foreign_key user_table, column: :owner_id if constrained
      end
      owners.each { |owner| owner.has_many(table.to_sym, as: :owner, class_name: name) }
      define_class(name, ActiveRecord::Base) { belongs_to :owner, polymorphic: true, optional: false }
    end

    it 'bakes the owner as the class the constraint references, every time' do
      application = define_application('Owned', owners: [user_model, account_model], constrained: true)

      owners = Array.new(5) { FactoryBakery.bake!(application).owner }

      expect(owners).to all(be_a(user_model))
    end

    it 'falls back to the one loaded model the constraint references when no candidate matches' do
      application = define_application('Orphan', owners: [account_model], constrained: true)

      record = FactoryBakery.bake!(application)

      expect(record.owner).to be_a(user_model)
    end

    it 'keeps every candidate when no constraint covers the owner id' do
      application = define_application('Plain', owners: [user_model, account_model], constrained: false)

      record = FactoryBakery.bake(application)

      expect([user_model, account_model]).to include(record.owner.class)
    end
  end
end
