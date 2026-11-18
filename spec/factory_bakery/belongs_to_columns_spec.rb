# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'FactoryBakery belongs_to columns' do
  include DefineConstantMacros

  let!(:account_model) { define_model('Account', name: :string) }

  describe 'an optional belongs_to backed by a real FK constraint' do
    let!(:user_model) do
      create_table(:users) do |t|
        t.references :account, foreign_key: true
        t.string :name
        t.integer :quantity
      end
      define_class('User', ActiveRecord::Base) { belongs_to :account, optional: true }
    end

    before { ActiveRecord::Base.connection.execute('PRAGMA foreign_keys = ON') }

    it 'leaves the FK nil after bake' do
      expect(FactoryBakery.bake(user_model).account_id).to be_nil
    end

    it 'bakes! successfully without violating the FK constraint' do
      expect { FactoryBakery.bake!(user_model) }.not_to raise_error
      expect(user_model.count).to eq(1)
      expect(user_model.first.account_id).to be_nil
    end

    it 'still fills integer columns that are not FKs' do
      record = FactoryBakery.bake(user_model)

      expect(record.quantity).to be_a(Integer)
      expect(record.quantity).to be_between(1, 100).inclusive
    end

    it 'applies a call-site FK override' do
      expect(FactoryBakery.bake(user_model, account_id: 42).account_id).to eq(42)
    end

    it 'applies a declaration of the FK' do
      FactoryBakery.define(user_model) { account_id { 7 } }

      expect(FactoryBakery.bake(user_model).account_id).to eq(7)
    end

    it 'applies a declaration of the association' do
      parent = account_model.new(name: 'declared')
      FactoryBakery.define(user_model) { account { parent } }

      expect(FactoryBakery.bake(user_model).account).to eq(parent)
    end

    it 'applies a call-site association override' do
      parent = account_model.new(name: 'override')

      expect(FactoryBakery.bake(user_model, account: parent).account).to eq(parent)
    end
  end

  describe 'a composite belongs_to FK' do
    let!(:child_model) do
      create_table(:composite_children) do |t|
        t.integer :account_id
        t.integer :account_tenant_id
        t.string :name
      end
      define_class('CompositeChild', ActiveRecord::Base) do
        belongs_to :account, foreign_key: %i[account_id account_tenant_id], optional: true
      end
    end

    it 'leaves every FK component nil' do
      record = FactoryBakery.bake(child_model)

      expect([record.account_id, record.account_tenant_id]).to eq([nil, nil])
      expect(record.name).to be_a(String)
    end
  end

  describe 'an optional polymorphic belongs_to' do
    let!(:comment_model) do
      create_table(:comments) do |t|
        t.references :commentable, polymorphic: true
        t.string :body
      end
      define_class('Comment', ActiveRecord::Base) do
        belongs_to :commentable, polymorphic: true, optional: true
      end
    end

    it 'leaves both the type and the id nil after bake' do
      record = FactoryBakery.bake(comment_model)

      expect([record.commentable_type, record.commentable_id]).to eq([nil, nil])
    end

    it 'bakes! successfully without a garbage type constant' do
      expect { FactoryBakery.bake!(comment_model) }.not_to raise_error
      expect(comment_model.count).to eq(1)
    end

    it 'applies call-site overrides of the type and id' do
      record = FactoryBakery.bake(comment_model, commentable_type: 'Account', commentable_id: 5)

      expect([record.commentable_type, record.commentable_id]).to eq(['Account', 5])
    end

    it 'applies a declaration of the type column' do
      FactoryBakery.define(comment_model) { commentable_type { 'Account' } }

      expect(FactoryBakery.bake(comment_model).commentable_type).to eq('Account')
    end

    it 'applies a declaration of the polymorphic association' do
      parent = account_model.new(name: 'parent')
      FactoryBakery.define(comment_model) { commentable { parent } }

      record = FactoryBakery.bake(comment_model)

      expect(record.commentable).to eq(parent)
      expect(record.commentable_type).to eq('Account')
    end
  end

  describe 'a required belongs_to with no declaration' do
    let!(:required_model) do
      define_model('RequiredUser', account_id: :integer) do
        belongs_to :account, optional: false
      end
    end

    it 'still fails validation with Rails must exist message' do
      record = FactoryBakery.bake(required_model)

      expect(record).not_to be_valid
      expect(record.errors[:account]).to include('must exist')
      expect { FactoryBakery.bake!(required_model) }
        .to raise_error(ActiveRecord::RecordInvalid, /Account must exist/)
    end
  end

  describe 'PORO targets' do
    it 'keeps heuristic filling for validator-covered attributes' do
      poro = define_class('PoroWithAccountId') do
        include ActiveModel::Model

        attr_accessor :account_id, :quantity
        validates :account_id, :quantity, numericality: { only_integer: true }
      end

      record = FactoryBakery.bake(poro)

      expect(record.account_id).to be_a(Integer)
      expect(record.quantity).to be_a(Integer)
    end
  end
end
