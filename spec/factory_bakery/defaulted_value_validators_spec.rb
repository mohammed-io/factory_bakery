# frozen_string_literal: true

require 'spec_helper'

# W1 (issue #41): a database default must not short-circuit to NoopFiller when
# a value-shaping validator constrains the attribute. Only when NO such
# validator applies does the DB default win (V2's presence escape hatch is a
# member of this broader set).
RSpec.describe 'defaulted columns with value-shaping validators (issue #41)' do
  include DefineConstantMacros

  describe 'defaulted + format' do
    let!(:model) do
      define_model('DefaultedFormatCode', code: { type: :string, default: '' }) do
        validates :code, format: { with: /\A[A-Z]{3}-\d{4}\z/ }
      end
    end

    it 'bakes a regex-compliant value instead of the blank default' do
      allow(FFaker::String).to receive(:from_regexp).and_return('ABC-1234')

      record = FactoryBakery.bake(model)

      expect(record.code).to eq('ABC-1234')
      expect(record.code).to match(/\A[A-Z]{3}-\d{4}\z/)
      expect(record).to be_valid
    end
  end

  describe 'defaulted + length' do
    let!(:model) do
      define_model('DefaultedLengthCode', code: { type: :string, default: '' }) do
        validates :code, length: { minimum: 7 }
      end
    end

    it 'bakes a value satisfying the length instead of the blank default' do
      allow(FFaker::Lorem).to receive(:word).and_return('ab')

      record = FactoryBakery.bake(model)

      expect(record.code.length).to be >= 7
      expect(record.code).not_to eq('')
      expect(record).to be_valid
    end
  end

  describe 'defaulted + uniqueness (V1 interplay)' do
    let!(:model) do
      define_model('DefaultedUniqueCode', code: { type: :string, default: '' }) do
        validates :code, uniqueness: true
      end
    end

    it 'produces two distinct persisted records instead of colliding on the default' do
      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'alpha', 'beta')

      first = FactoryBakery.bake!(model)
      second = FactoryBakery.bake!(model)

      expect(first.code).to eq('alpha')
      expect(second.code).to eq('beta')
      expect(first.code).not_to eq(second.code)
      expect(first).to be_persisted
      expect(second).to be_persisted
      expect(model.count).to eq(2)
      expect(first).to be_valid
      expect(second).to be_valid
    end
  end

  describe 'defaulted + inclusion' do
    let!(:model) do
      define_model('DefaultedInclusionStatus', status: { type: :string, default: '' }) do
        validates :status, inclusion: { in: %w[active archived] }
      end
    end

    it 'bakes a member of the allowed set instead of the blank default' do
      record = FactoryBakery.bake(model)

      expect(%w[active archived]).to include(record.status)
      expect(record).to be_valid
    end
  end

  describe 'defaulted + exclusion' do
    let!(:model) do
      define_model('DefaultedExclusionCode', code: { type: :string, default: 'reserved' }) do
        validates :code, exclusion: { in: ['reserved'] }
      end
    end

    it 'bakes a value outside the forbidden set instead of the default' do
      allow(FFaker::Lorem).to receive(:word).and_return('reserved', 'allowed')

      record = FactoryBakery.bake(model)

      expect(record.code).to eq('allowed')
      expect(record).to be_valid
    end
  end

  describe 'defaulted + numericality' do
    let!(:model) do
      define_model('DefaultedNumericCount', count: { type: :integer, default: 0 }) do
        validates :count, numericality: { only_integer: true, greater_than: 10 }
      end
    end

    it 'bakes a value satisfying the bound instead of the default' do
      record = FactoryBakery.bake(model)

      expect(record.count).to be > 10
      expect(record.count).not_to eq(0)
      expect(record).to be_valid
    end
  end

  describe 'defaulted + comparison' do
    let!(:model) do
      define_model('DefaultedCompareCount', count: { type: :integer, default: 0 }) do
        validates :count, comparison: { greater_than: 50 }
      end
    end

    it 'bakes a value satisfying the bound instead of the default' do
      record = FactoryBakery.bake(model)

      expect(record.count).to be > 50
      expect(record.count).not_to eq(0)
      expect(record).to be_valid
    end
  end

  describe 'CustomEmoji#shortcode repro (defaulted + format + length + uniqueness)' do
    let!(:model) do
      define_model('DefaultedCustomEmoji', shortcode: { type: :string, default: '' }) do
        validates :shortcode, format: { with: /\A[a-z0-9_]+\z/ }
        validates :shortcode, length: { minimum: 2 }
        validates :shortcode, uniqueness: true
      end
    end

    it 'bakes valid, format-compliant, distinct shortcodes' do
      values = %w[emoji_ab12 emoji_cd34 emoji_ef56]
      index = 0
      allow(FFaker::String).to receive(:from_regexp) do
        value = values[index]
        index += 1
        value
      end

      first = FactoryBakery.bake!(model)
      second = FactoryBakery.bake!(model)

      expect(first.shortcode).to match(/\A[a-z0-9_]+\z/)
      expect(second.shortcode).to match(/\A[a-z0-9_]+\z/)
      expect(first.shortcode.length).to be >= 2
      expect(second.shortcode.length).to be >= 2
      expect(first.shortcode).not_to eq(second.shortcode)
      expect(first).to be_valid
      expect(second).to be_valid
    end
  end

  describe 'defaulted with NO validators (guard)' do
    let!(:model) do
      define_model('DefaultedPlainStatus', status: { type: :string, default: 'draft' })
    end

    it 'keeps today behavior: the database default wins' do
      record = FactoryBakery.bake(model)

      expect(record.status).to eq('draft')
    end
  end

  describe 'V2 presence behavior (guard)' do
    let!(:model) do
      define_model('DefaultedPresentStatus', status: { type: :string, default: '' }) do
        validates :status, presence: true
      end
    end

    it 'still generates a present value that outranks the blank default' do
      records = 20.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:status)).to all(be_present)
      expect(records).to all(be_valid)
    end
  end

  describe 'absence still wins when flagged (guard)' do
    let!(:model) do
      define_model('DefaultedAbsentFlag', flag: { type: :boolean, default: false }) do
        validates :flag, absence: true
        validates :flag, presence: true
      end
    end

    it 'still emits nil even though presence is in the value-shaping set' do
      record = FactoryBakery.bake(model)

      expect(record.flag).to be_nil
    end
  end
end
