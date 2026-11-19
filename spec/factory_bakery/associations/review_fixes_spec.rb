# frozen_string_literal: true

require 'spec_helper'
require 'factory_bakery/associations'

# Public-API coverage for three verified review findings: a failed polymorphic
# candidate must not leak records into the winning build, a required natural
# key with a nullable FK column must still produce a valid record, and an
# empty polymorphic discovery result must not be cached for the process.
RSpec.describe 'FactoryBakery association review fixes' do
  # A stand-in for the Rails application's one-time eager load: it can define
  # models (the real eager load loads files that do) and fail once on demand.
  let(:fake_eager_app) do
    Struct.new(:on_load, :fail_next, keyword_init: true) do
      def eager_load!
        raise 'eager load failed' if fail_next

        on_load&.call
      end
    end
  end

  before do
    FactoryBakery.reset_plugins!
    FactoryBakery.register_plugin(FactoryBakery::Associations::Plugin)
    FactoryBakery::Associations.mode = :required_only
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

  describe 'a polymorphic candidate that fails after generating records' do
    it 'persists the winning candidate under bake! and rolls the failed candidate back' do
      # The failing candidate builds two parents: one persisted because the raw
      # FK is validated (an orphan row if not rolled back) and one left unsaved
      # because only the association is validated (an IncompletePersistenceError
      # if the failed candidate's records are not discarded).
      owner_class = define_model('ReviewFixOwnerx', name: :string)
      uncle_class = define_model('ReviewFixUncle', name: :string)
      define_model('ReviewFixBadTarget', ownerx_id: :integer, uncle_id: :integer, code: :string) do
        belongs_to :ownerx, class_name: 'ReviewFixOwnerx', optional: true
        belongs_to :uncle, class_name: 'ReviewFixUncle', optional: false
        validates :ownerx_id, presence: true
        validates :code, format: { with: /\Afoo(?=bar)\z/ }
      end
      good_class = define_model('ReviewFixGoodTarget', name: :string)
      comment = define_model('ReviewFixComment', commentable_type: :string, commentable_id: :integer) do
        belongs_to :commentable, polymorphic: true, optional: false
        validates :commentable_type, inclusion: { in: %w[ReviewFixBadTarget ReviewFixGoodTarget] }
      end

      record = FactoryBakery.bake!(comment)

      expect(record).to be_persisted
      expect(record.commentable).to be_a(good_class)
      expect(record.commentable).to be_persisted
      expect(record).to be_valid
      expect(owner_class.count).to eq(0)
      expect(uncle_class.count).to eq(0)
    end
  end

  describe 'a required natural key with a nullable foreign key column' do
    it 'generates the key and builds a parent that shares it' do
      parent_class = define_model('ReviewFixInstance', domain: { type: :string, null: false })
      note = define_model('ReviewFixNote', host: :string) do
        belongs_to :instance, class_name: 'ReviewFixInstance',
                              foreign_key: :host, primary_key: :domain, optional: false
      end

      record = FactoryBakery.bake(note)

      expect(record.host).to be_a(String)
      expect(record.host).not_to be_empty
      expect(record.instance).to be_a(parent_class)
      expect(record.instance.domain).to eq(record.host)
      expect(record).to be_valid
    end

    it 'leaves the column unset when the foreign key is explicitly skipped' do
      define_model('ReviewFixSkipInstance', domain: { type: :string, null: false })
      note = define_model('ReviewFixSkipNote', host: :string) do
        belongs_to :instance, class_name: 'ReviewFixSkipInstance',
                              foreign_key: :host, primary_key: :domain, optional: false
      end
      FactoryBakery.define(note) { skip :host }

      record = FactoryBakery.bake(note)

      expect(record.host).to be_nil
      expect(record.instance).to be_nil
    end

    it 'propagates a call-site foreign key override' do
      define_model('ReviewFixOverrideInstance', domain: { type: :string, null: false })
      note = define_model('ReviewFixOverrideNote', host: :string) do
        belongs_to :instance, class_name: 'ReviewFixOverrideInstance',
                              foreign_key: :host, primary_key: :domain, optional: false
      end

      record = FactoryBakery.bake(note, host: 'review.test')

      expect(record.host).to eq('review.test')
      expect(record.instance.domain).to eq('review.test')
      expect(record).to be_valid
    end
  end

  describe 'polymorphic discovery caching' do
    it 'does not cache an empty result once an owner appears' do
      link = define_model('ReviewFixCacheLink', review_thing_type: :string, review_thing_id: :integer) do
        belongs_to :review_thing, polymorphic: true, optional: false
      end

      expect { FactoryBakery.bake(link) }
        .to raise_error(FactoryBakery::Error, /required polymorphic.*review_thing/)

      owner = define_model('ReviewFixCacheOwner', name: :string) do
        has_one :review_cache_link, as: :review_thing, class_name: 'ReviewFixCacheLink'
      end

      expect(FactoryBakery.bake(link).review_thing).to be_a(owner)
    end

    it 'finds a target through eager loading after a non-eager attempt found nothing' do
      link = define_model('ReviewFixEagerLink', eager_thing_type: :string, eager_thing_id: :integer) do
        belongs_to :eager_thing, polymorphic: true, optional: false
      end
      app = fake_eager_app.new(on_load: lambda do
        define_model('ReviewFixEagerOwner', name: :string) do
          has_one :review_eager_link, as: :eager_thing, class_name: 'ReviewFixEagerLink'
        end
      end)
      allow(Rails).to receive(:application).and_return(app)

      FactoryBakery::Associations.eager_load = false
      expect { FactoryBakery.bake(link) }.to raise_error(FactoryBakery::Error, /required polymorphic/)

      FactoryBakery::Associations.eager_load = true
      record = FactoryBakery.bake(link)

      expect(record.eager_thing).to be_a(Object.const_get('ReviewFixEagerOwner'))
      expect(record).to be_valid
    end

    it 'eager loads again after a failed eager load' do
      link = define_model('ReviewFixRaiseLink', raisable_type: :string, raisable_id: :integer) do
        belongs_to :raisable, polymorphic: true, optional: false
      end
      app = fake_eager_app.new(fail_next: true)
      app.on_load = lambda do
        define_model('ReviewFixRaisableOwner', name: :string) do
          has_one :review_raisable_link, as: :raisable, class_name: 'ReviewFixRaiseLink'
        end
      end
      allow(Rails).to receive(:application).and_return(app)
      FactoryBakery::Associations.eager_load = true

      expect { FactoryBakery.bake(link) }.to raise_error(RuntimeError, /eager load failed/)

      app.fail_next = false
      expect(FactoryBakery.bake(link).raisable).to be_a(Object.const_get('ReviewFixRaisableOwner'))
    end
  end
end
