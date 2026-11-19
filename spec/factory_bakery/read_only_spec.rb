# frozen_string_literal: true

require 'spec_helper'
require 'factory_bakery/associations'

# Public-API behavior for issue #55: read-only targets (models whose readonly?
# is true, e.g. database views) are first-class bake targets. bake! refuses to
# write them with a clear error before anything is persisted.
RSpec.describe 'read-only bake targets' do
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

  it 'bake populates a read-only model and leaves it valid and unsaved' do
    model = define_model('ViewInstance', domain: { type: :string, null: false },
                                         accounts_count: { type: :integer, null: false }) do
      validates :domain, presence: true
      validates :accounts_count, presence: true

      def readonly? = true
    end

    record = FactoryBakery.bake(model)

    expect(record).to be_a(model)
    expect(record).to be_new_record
    expect(record.domain).to be_a(String)
    expect(record.domain).not_to be_empty
    expect(record.accounts_count).to be_a(Integer)
    expect(record).to be_valid
    expect(model.count).to eq(0)
  end

  it 'bake! raises a clear error and writes nothing for a read-only root' do
    parent = define_model('ViewOwner', name: :string)
    model = define_model('ViewNote', name: :string, owner_id: :integer) do
      belongs_to :owner, class_name: 'ViewOwner', optional: false

      def readonly? = true
    end

    expect { FactoryBakery.bake!(model) }
      .to raise_error(FactoryBakery::ReadOnlyTargetError) { |error|
        expect(error).to be_a(FactoryBakery::Error)
        expect(error.message).to include('ViewNote is read-only')
        expect(error.message).to include('readonly? is true')
        expect(error.message).to include('use FactoryBakery.bake')
        expect(error.message).to include('persist_with')
      }

    expect(model.count).to eq(0)
    expect(parent.count).to eq(0)
  end

  it 'raises for a read-only root without the associations plugin' do
    FactoryBakery.reset_plugins!
    model = define_model('ViewBare', name: :string) do
      def readonly? = true
    end

    expect { FactoryBakery.bake!(model) }
      .to raise_error(FactoryBakery::ReadOnlyTargetError, /ViewBare is read-only/)
    expect(model.count).to eq(0)
  end

  it 'rolls back a parent inserted before the read-only check' do
    parent = define_model('ViewFkParent', name: :string)
    model = define_model('ViewFkChild', name: :string, parent_id: :integer) do
      belongs_to :parent, class_name: 'ViewFkParent', optional: true
      validates :parent_id, presence: true

      def readonly? = true
    end

    expect { FactoryBakery.bake!(model) }
      .to raise_error(FactoryBakery::ReadOnlyTargetError, /ViewFkChild is read-only/)

    expect(model.count).to eq(0)
    expect(parent.count).to eq(0)
  end

  it 'detects read-only on the instance, not just for every instance of the class' do
    model = define_model('ViewConditional', domain: :string) do
      def readonly? = domain == 'locked'
    end

    expect { FactoryBakery.bake!(model, domain: 'locked') }
      .to raise_error(FactoryBakery::ReadOnlyTargetError, /ViewConditional is read-only/)
    expect(model.count).to eq(0)

    record = FactoryBakery.bake!(model, domain: 'open')
    expect(record).to be_persisted
    expect(model.count).to eq(1)
  end

  it 'bake! names the chain when a required read-only parent is auto-built' do
    instance = define_model('ViewModerationInstance', domain: { type: :string, null: false }) do
      validates :domain, presence: true

      def readonly? = true
    end
    note = define_model('ViewModerationNote', domain: { type: :string, null: false }) do
      belongs_to :instance, class_name: 'ViewModerationInstance',
                            foreign_key: :domain, primary_key: :domain, optional: false
    end

    expect { FactoryBakery.bake!(note) }
      .to raise_error(FactoryBakery::ReadOnlyTargetError,
                      /ViewModerationNote#instance -> ViewModerationInstance is read-only/)

    expect(note.count).to eq(0)
    expect(instance.count).to eq(0)
  end

  it 'bake! names an id-keyed required read-only parent chain too' do
    parent = define_model('ViewIdParent', name: :string) do
      def readonly? = true
    end
    child = define_model('ViewIdChild', name: :string, parent_id: :integer) do
      belongs_to :parent, class_name: 'ViewIdParent', optional: false
    end

    expect { FactoryBakery.bake!(child) }
      .to raise_error(FactoryBakery::ReadOnlyTargetError,
                      /ViewIdChild#parent -> ViewIdParent is read-only/)

    expect(child.count).to eq(0)
    expect(parent.count).to eq(0)
  end
end
