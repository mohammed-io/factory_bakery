# frozen_string_literal: true

require 'spec_helper'
require 'factory_bakery/associations'

# Public-API coverage for polymorphic target discovery (#60): inclusion
# validators, inverse `as:` reflections (including STI class_name matching),
# deterministic choice, actionable errors, precedence and caching. The mapper's
# descendants source is stubbed where inverses matter so stale classes from
# other examples cannot win, and so the cache is observable.
RSpec.describe 'FactoryBakery polymorphic association discovery' do
  before do
    FactoryBakery.reset_plugins!
    FactoryBakery.register_plugin(FactoryBakery::Associations::Plugin)
    FactoryBakery::Associations.mode = :required_only
    FactoryBakery::Associations.eager_load = false
    discovery.reset!
  end

  after do
    FactoryBakery.reset_plugins!
    FactoryBakery::Associations.reset_configuration!
    discovery.reset!
  end

  def discovery
    FactoryBakery::ActiveRecordMapper::PolymorphicTargetDiscovery
  end

  def stub_descendants(*classes)
    allow(discovery).to receive(:descendants).and_return(classes)
  end

  def define_link(prefix, association = :target, type_column = :target_type)
    define_model("#{prefix}Link", type_column => :string, "#{association}_id" => :integer) do
      belongs_to association, polymorphic: true, optional: false
    end
  end

  describe 'discovery sources' do
    it 'picks a class named by an inclusion validator on the type column' do
      post_model = define_model('PolyIncPost', title: :string)
      link_model = define_model('PolyIncSource', target_type: :string, target_id: :integer) do
        belongs_to :target, polymorphic: true, optional: false
        validates :target_type, inclusion: { in: %w[PolyIncPost] }
      end

      record = FactoryBakery.bake!(link_model)

      expect(record.target).to be_a(post_model)
      expect(record.target_type).to eq(post_model.polymorphic_name)
      expect(record).to be_valid
    end

    it 'orders inclusion candidates by name regardless of their declared order' do
      define_model('PolyOrderZed', name: :string)
      alpha_model = define_model('PolyOrderAlpha', name: :string)
      link_model = define_model('PolyOrderLink', linkable_type: :string, linkable_id: :integer) do
        belongs_to :linkable, polymorphic: true, optional: false
        validates :linkable_type, inclusion: { in: %w[PolyOrderZed PolyOrderAlpha] }
      end

      expect(FactoryBakery.bake(link_model).linkable).to be_a(alpha_model)
    end

    it 'picks the owner whose as: inverse names the baked STI subclass' do
      stub_const('PolyChat', Module.new)
      channel = define_model('PolyChatChannel', type: :string, chatable_type: :string, chatable_id: :integer) do
        belongs_to :chatable, polymorphic: true, optional: false
      end
      category = define_model('PolyCategory', name: :string) do
        has_one :category_channel, as: :chatable, class_name: 'PolyChat::CategoryChannel'
      end
      direct_message = define_model('PolyDirectMessage', name: :string) do
        has_one :direct_message_channel, as: :chatable, class_name: 'PolyChat::DirectMessageChannel'
      end
      category_channel = define_class('PolyChat::CategoryChannel', channel)
      define_class('PolyChat::DirectMessageChannel', channel)
      stub_descendants(category, direct_message)

      record = FactoryBakery.bake!(category_channel)

      expect(record.chatable).to be_a(category)
      expect(record.chatable_type).to eq(category.polymorphic_name)
      expect([record.persisted?, record.chatable.persisted?]).to eq([true, true])
      expect(record).to be_valid
    end

    it 'chooses deterministically among several inverse candidates' do
      channel = define_link('PolySeveral', :chatable, :chatable_type)
      zeta = define_model('PolyZetaOwner', name: :string) do
        has_one :zeta_channel, as: :chatable, class_name: 'PolySeveralLink'
      end
      alpha = define_model('PolyAlphaOwner', name: :string) do
        has_one :alpha_channel, as: :chatable, class_name: 'PolySeveralLink'
      end
      stub_descendants(zeta, alpha)

      first = FactoryBakery.bake(channel)
      discovery.reset!
      second = FactoryBakery.bake(channel)

      expect([first.chatable.class, second.chatable.class]).to eq([alpha, alpha])
    end
  end

  describe 'errors and precedence' do
    it 'keeps the actionable error and lists every discovery source when nothing is found' do
      owner = define_model('PolyNoInverseOwner', name: :string)
      link_model = define_link('PolyNoInverse', :linkable, :linkable_type)
      stub_descendants(owner)

      expect { FactoryBakery.bake(link_model) }.to raise_error(FactoryBakery::Error) { |error|
        expect(error.message).to match(/required polymorphic.*linkable/)
        expect(error.message).to match(/association :linkable, factory:/)
        expect(error.message).to match(/linkable:/)
        expect(error.message).to include('inclusion validator on linkable_type')
        expect(error.message).to include('inverse as: reflections')
        expect(error.message).to include('Rails.application.eager_load!')
      }
    end

    it 'lets an explicit factory declaration win over discovery' do
      link_model = define_link('PolyDeclared', :chatable, :chatable_type)
      chosen = define_model('PolyDeclaredChosen', name: :string)
      define_model('PolyDeclaredOwner', name: :string) do
        has_one :declared_channel, as: :chatable, class_name: 'PolyDeclaredLink'
      end
      FactoryBakery.define(link_model) { association :chatable, factory: chosen }

      expect(FactoryBakery.bake(link_model).chatable).to be_a(chosen)
    end

    it 'lets a call-site assignment and skip win over discovery' do
      link_model = define_link('PolyOverride', :chatable, :chatable_type)
      owner = define_model('PolyOverrideOwner', name: :string) do
        has_one :override_channel, as: :chatable, class_name: 'PolyOverrideLink'
      end
      stub_descendants(owner)
      existing = owner.create!(name: 'existing')

      assigned = FactoryBakery.bake(link_model, chatable: existing)
      expect(assigned.chatable).to equal(existing)

      FactoryBakery.define(link_model) { skip :chatable }
      expect(FactoryBakery.bake(link_model).chatable).to be_nil
    end

    it 'reuses an existing row of a discovered candidate under :reuse_non_unique' do
      link_model = define_link('PolyReuse', :chatable, :chatable_type)
      owner = define_model('PolyReuseOwner', name: :string) do
        has_one :reuse_channel, as: :chatable, class_name: 'PolyReuseLink'
      end
      stub_descendants(owner)
      existing = owner.create!(name: 'existing')

      record = FactoryBakery::Associations.with(strategy: :reuse_non_unique) { FactoryBakery.bake(link_model) }

      expect(record.chatable).to eq(existing)
      expect(owner.count).to eq(1)
    end
  end

  it 'caches discovery for the process, scanning descendants only once' do
    link_model = define_link('PolyCached', :chatable, :chatable_type)
    owner = define_model('PolyCachedOwner', name: :string) do
      has_one :cached_channel, as: :chatable, class_name: 'PolyCachedLink'
    end
    stub_descendants(owner)

    first = FactoryBakery.bake(link_model)
    second = FactoryBakery.bake(link_model)

    expect([first.chatable.class, second.chatable.class]).to eq([owner, owner])
    expect(discovery).to have_received(:descendants).once
  end
end
