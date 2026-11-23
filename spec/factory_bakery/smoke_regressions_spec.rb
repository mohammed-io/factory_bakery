# frozen_string_literal: true

require 'spec_helper'
require 'factory_bakery/associations'

# Regressions found against real Mastodon and Discourse apps. Each example
# goes through the public bake/bake!/define API and small schema-backed models
# that reproduce the same shape: a lazily defined acceptance attribute, a
# nested parent whose optional fill would invalidate it, an unsaved parent
# shared into a nested `bake!` graph, and a unique index without a uniqueness
# validator.
RSpec.describe 'smoke regressions' do
  include DefineConstantMacros

  after { FactoryBakery.fill_optional = false }

  it 'preserves a required boolean default on a column ending in _confirmation' do
    board = define_model('ConfirmationDefaultBoard',
                         require_confirmation: { type: :boolean, null: false, default: true })

    expect(FactoryBakery.bake!(board).reload.require_confirmation).to be(true)
  end

  it 'generates a value for a required confirmation-suffixed column without a source attribute' do
    board = define_model('ConfirmationRequiredBoard', require_confirmation: { type: :boolean, null: false })

    expect(FactoryBakery.bake!(board).reload.require_confirmation).to be_in([true, false])
  end

  describe 'a lazily defined acceptance attribute' do
    # Mastodon's User validates an `agreement` virtual attribute but never
    # defines the accessor: ActiveModel::Validations::AcceptanceValidator
    # defines it the first time the class is validated. The mapper must still
    # discover and fill it.
    it 'fills an acceptance attribute whose writer the validator defines lazily' do
      model = define_model('LazyAcceptance', name: :string) do
        validates :name, presence: true
        validates :agreement, acceptance: { allow_nil: false, accept: [true, 'true', '1'] }, on: :create
      end

      record = FactoryBakery.bake(model)

      expect(record.agreement).to be(true)
      expect(record).to be_valid
    end
  end

  describe 'the verified fallback rebuild' do
    # The lean child is invalid until an optional column is filled, so the
    # fallback rebuilds with optional columns on. The parent is built by a
    # declaration inside that rebuild; it is a separate record with its own
    # fallback, so the rebuild must not turn it into a fuller record that
    # fails its own validation.
    it 'keeps a nested parent lean instead of filling its optional columns' do
      parent = define_model('RebuildLeanParent', name: :string, domain: :string, inbox_url: :string) do
        validates :name, presence: true
        validates :inbox_url, presence: true, if: -> { domain.present? }
      end
      child = define_model('RebuildLeanChild', name: :string, extra: :string, parent_id: :integer) do
        attr_accessor :agreement

        belongs_to :parent, class_name: 'RebuildLeanParent', optional: false
        accepts_nested_attributes_for :parent

        validates :name, presence: true
        validates :agreement, acceptance: { allow_nil: false, accept: [true, 'true', '1'] }, on: :create
        validate { errors.add(:extra, :blank) if extra.nil? }
      end
      FactoryBakery.define(child) { parent { FactoryBakery.bake(parent) } }

      record = FactoryBakery.bake(child)

      expect(record.extra).to be_present
      expect(record.agreement).to be(true)
      expect(record.parent.domain).to be_nil
      expect(record.parent).to be_valid
      expect(record).to be_valid
    end

    it 'does not reuse a parent left behind by a discarded savepoint attempt' do
      parent = define_model('RebuildDiscardParent', name: :string)
      child = define_model('RebuildDiscardChild', name: :string, token: :string, secret: :string) do
        attr_accessor :parent

        validates :name, presence: true
        validate { errors.add(:base, 'a credential must be selected') if token.nil? && secret.nil? }
      end
      FactoryBakery.define(child) { parent { FactoryBakery.bake!(parent) } }

      record = FactoryBakery.bake!(child)

      expect(record.token).to be_present
      expect(record.parent).to be_persisted
      expect(parent.count).to eq(1)
    end
  end

  describe 'nested bake! with in-graph parents' do
    before do
      FactoryBakery.reset_plugins!
      FactoryBakery.register_plugin(FactoryBakery::Associations::Plugin)
      FactoryBakery::Associations.reset_configuration!
    end

    after do
      FactoryBakery.reset_plugins!
      FactoryBakery::Associations.reset_configuration!
    end

    # Widget belongs_to owner and part; Part belongs_to the same owner and
    # has_one widget (inverse). Sharing the unsaved owner between Widget and
    # Part closes an autosave cycle: saving the owner saves its new Part,
    # whose has_one Widget is saved before Widget's own owner autosave has
    # filled owner_id. Under bake! only an already persisted parent may be
    # shared, so Part builds its own owner and the cycle never forms.
    def define_widget_graph(prefix)
      owner = define_model("#{prefix}Owner", name: :string) do
        has_many :parts, class_name: "#{prefix}Part", foreign_key: :owner_id, inverse_of: :owner
      end
      part = define_model("#{prefix}Part", name: :string, owner_id: { type: :integer, null: false }) do
        belongs_to :owner, class_name: "#{prefix}Owner", optional: false, inverse_of: :parts
        has_one :widget, class_name: "#{prefix}Widget", foreign_key: :part_id, inverse_of: :part
      end
      widget = define_model("#{prefix}Widget",
                            title: :string,
                            owner_id: { type: :integer, null: false },
                            part_id: { type: :integer, null: false }) do
        belongs_to :owner, class_name: "#{prefix}Owner", optional: false
        belongs_to :part, class_name: "#{prefix}Part", optional: false, inverse_of: :widget
      end
      bundle = define_model("#{prefix}Bundle", name: :string) { attr_accessor :widget }
      [owner, part, widget, bundle]
    end

    it 'never hands a nested bake! an unsaved shared parent' do
      _owner, _part, widget, bundle = define_widget_graph('SmokeNestedWidget')
      FactoryBakery.define(bundle) { widget { FactoryBakery.bake!(widget) } }

      baked = FactoryBakery.bake(bundle)

      expect(baked.widget).to be_persisted
      expect(baked.widget.owner_id).to be_present
      expect(baked.widget.part_id).to be_present
      expect(baked.widget.owner).to be_persisted
      expect(baked.widget.part).to be_persisted
    end
  end

  describe 'a unique index without a uniqueness validator' do
    # Discourse's users.secure_identifier is nullable with a single-column
    # UNIQUE index and no `validates ... uniqueness:`. The enforcer must still
    # keep the generated value out of the database.
    it 'regenerates a value that the database already holds' do
      model = define_model('SmokeUniqueIndex', code: :string)
      ActiveRecord::Base.connection.add_index(model.table_name, :code, unique: true)
      model.create!(code: 'ex')
      allow(FFaker::Lorem).to receive(:word).and_return('ex')

      record = FactoryBakery.bake!(model)

      expect(record.code).not_to eq('ex')
      expect(record).to be_persisted
      expect(model.where(code: 'ex').count).to eq(1)
    end
  end

  describe 'a virtual inclusion attribute whose filled value a custom validation rejects' do
    # Discourse's LlmModel#requested_vision_mode is an attr_accessor with an
    # inclusion validator that allows nil, and a `validate` block that rejects a
    # non-nil value ("a vision model must be selected"). The lean record is
    # invalid for an unrelated reason (missing credential), so the verified
    # fallback rebuilds with optional columns filled, and the rebuild fills
    # requested_vision_mode. The rebuild's error lands on :base, not on the
    # filled attribute, so the fill must still be put back to nil.
    it 'leaves the virtual attribute nil instead of returning the rejected fill' do
      model = define_model('SmokeVirtualVision', name: :string, api_key: :string) do
        attr_accessor :requested_vision_mode

        validates :name, presence: true
        validates :requested_vision_mode,
                  inclusion: { in: %w[disabled delegated native] },
                  allow_nil: true
        validate { errors.add(:base, 'a credential must be selected') if api_key.blank? }
        validate { errors.add(:base, 'a vision model must be selected') if requested_vision_mode.present? }
      end

      record = FactoryBakery.bake(model)

      expect(record.api_key).to be_present
      expect(record.requested_vision_mode).to be_nil
      expect(record).to be_valid
    end
  end
end
