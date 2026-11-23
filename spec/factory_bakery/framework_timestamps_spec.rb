# frozen_string_literal: true

require 'spec_helper'

# ActiveRecord stamps created_at / updated_at itself on save, so a bake leaves
# them to the framework instead of generating random past times for them.
RSpec.describe 'framework-managed timestamps' do
  let(:timestamps) { { type: :datetime, null: false } }

  let!(:article) do
    define_model('TsArticle', title: :string, created_at: timestamps.dup, updated_at: timestamps.dup) do
      validates :title, presence: true
    end
  end

  it 'leaves the timestamps of an unsaved bake empty, like FactoryBot.build' do
    record = FactoryBakery.bake(article)

    expect([record.created_at, record.updated_at]).to all(be_nil)
    expect(record.title).to be_present
  end

  it 'lets ActiveRecord stamp "now" when the record is saved' do
    before = Time.now.utc - 1
    record = FactoryBakery.bake!(article)

    expect(record).to be_persisted
    expect(record.created_at).to be >= before
    expect(record.updated_at).to be >= before
  end

  it 'keeps an explicit override' do
    stamp = Time.utc(2020, 1, 2, 3, 4, 5)

    record = FactoryBakery.bake!(article, created_at: stamp)

    expect(record.created_at).to eq(stamp)
  end

  it 'keeps a value declared by a definition' do
    stamp = Time.utc(2019, 6, 7, 8, 9, 10)
    FactoryBakery.define(article) { created_at { stamp } }

    expect(FactoryBakery.bake(article).created_at).to eq(stamp)
  end

  it 'still fills a timestamp the model validates' do
    validated = define_model('TsValidated', created_at: timestamps.dup) do
      validates :created_at, presence: true
    end

    expect(FactoryBakery.bake(validated).created_at).to be_present
  end

  it 'still fills the timestamps of a model that turned record_timestamps off' do
    manual = define_model('TsManual', created_at: timestamps.dup, updated_at: timestamps.dup) do
      self.record_timestamps = false
    end

    record = FactoryBakery.bake!(manual)

    expect(record).to be_persisted
    expect(record.created_at).to be_present
  end

  it 'still fills a timestamp a custom validate method demands' do
    # Rails stamps the timestamps after validation, so a `validate` method that
    # requires created_at would fail the save if the gem left it to the
    # framework.
    demanded = define_model('TsCustomValidated', created_at: timestamps.dup) do
      validate :created_at_required

      def created_at_required
        errors.add(:created_at, :blank) if created_at.blank?
      end
    end

    expect(FactoryBakery.bake(demanded).created_at).to be_present
    expect(FactoryBakery.bake!(demanded).reload.created_at).to be_present
  end

  it 'still fills a timestamp a before_validation callback reads' do
    # Rails stamps the timestamps after validation, so a `before_validation`
    # that reads created_at would raise NoMethodError on a bake! if the gem
    # left the column nil.
    reader = define_model('TsCallbackReader', created_at: timestamps.dup, expires_on: :date) do
      before_validation { self.expires_on = created_at.to_date + 30 }
    end

    expect { FactoryBakery.bake(reader) }.not_to raise_error

    saved = FactoryBakery.bake!(reader)
    # The callback computed the date from the time as assigned (local zone) and
    # the saved column is read back in UTC, so the two dates can differ by one
    # calendar day depending on the time of day and the machine's zone.
    expect(saved.created_at).to be_present
    expect((saved.expires_on - saved.created_at.to_date).to_i).to be_between(29, 31)
  end

  it 'fills a NOT NULL timestamp again once a baked model turns record_timestamps off' do
    toggled = define_model('TsToggled', created_at: timestamps.dup)

    expect(FactoryBakery.bake(toggled).created_at).to be_nil

    toggled.record_timestamps = false

    expect(FactoryBakery.bake(toggled).created_at).to be_present
    expect(FactoryBakery.bake!(toggled)).to be_persisted
  end

  it 'does not touch other datetime columns' do
    event = define_model('TsEvent', starts_at: timestamps.dup)

    expect(FactoryBakery.bake(event).starts_at).to be_present
  end
end
