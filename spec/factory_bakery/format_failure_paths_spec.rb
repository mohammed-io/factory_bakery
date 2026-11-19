# frozen_string_literal: true

require 'spec_helper'
require 'active_model'

RSpec.describe 'format validator failure paths (issue #37)' do
  include DefineConstantMacros

  describe ':without is honored deterministically (audit probe 7)' do
    let!(:model) do
      define_model('WithoutPatternCode', code: :string) do
        validates :code, format: { without: /\Aadmin\z/ }
      end
    end

    it 'never emits a value matching the forbidden regex across repeated bakes' do
      allow(FFaker::Lorem).to receive(:word).and_return('admin', 'admin', 'member')

      records = 20.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:code)).to all(satisfy { |value| !value.match?(/\Aadmin\z/) })
      expect(records).to all(be_valid)
    end

    it 'raises a contextual error when every generated value is forbidden' do
      allow(FFaker::Lorem).to receive(:word).and_return('admin')

      expect { FactoryBakery.bake(model) }
        .to raise_error(FactoryBakery::Error, /WithoutPatternCode#code.*admin.*attempts/m)
    end
  end

  describe 'post-generation verification of :with (audit probe 6)' do
    let!(:model) do
      define_model('VerifiedFormatCode', code: :string) do
        validates :code, format: { with: /[a-z]+-\d+/ }
      end
    end

    it 'regenerates when the generator yields a value that does not match the regex' do
      allow(FactoryBakery::RegexGeneration).to receive(:generate).and_return('INVALID', 'ok-123')

      record = FactoryBakery.bake(model)

      expect(record.code).to eq('ok-123')
      expect(record).to be_valid
    end

    it 'keeps simple :with regexes working across repeated bakes' do
      records = 20.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:code)).to all(match(/[a-z]+-\d+/))
      expect(records).to all(be_valid)
    end

    it 'raises a contextual error naming the attribute and regex on exhaustion' do
      allow(FactoryBakery::RegexGeneration).to receive(:generate).and_return('short')

      expect { FactoryBakery.bake(model) }
        .to raise_error(FactoryBakery::Error, /VerifiedFormatCode#code.*\[a-z\].*attempts/m)
    end
  end

  describe 'length and format negotiation' do
    it 'satisfies both when the regex already produces the required length' do
      model = define_model('AlignedFormatLengthCode', code: :string) do
        validates :code, format: { with: /\A[a-z]{8}\z/ }
        validates :code, length: { is: 8 }
      end

      records = 20.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:code)).to all(match(/\A[a-z]{8}\z/))
      expect(records.map(&:code).map(&:length)).to all(eq(8))
      expect(records).to all(be_valid)
    end

    it 'raises instead of truncating a regex-compliant value to the database limit' do
      model = define_model('DbLimitFormatCode', short_code: { type: :string, limit: 5 }) do
        validates :short_code, format: { with: /\A[a-z]{8}\z/ }
      end

      expect { FactoryBakery.bake(model) }
        .to raise_error(FactoryBakery::Error, /DbLimitFormatCode#short_code.*\[a-z\]\{8\}.*attempts/m)
    end
  end

  describe 'format and uniqueness interplay' do
    it 'keeps regenerated values format-compliant when uniqueness retries' do
      model = define_model('UniqueFormatCode', code: :string) do
        validates :code, format: { with: /\A[A-Z]{3}-\d{4}\z/ }
        validates :code, uniqueness: true
      end

      # First bake: compliant + free. Second bake: collision, then no
      # candidate at all (nil), then a compliant + free value.
      values = ['ABC-1234', 'ABC-1234', nil, 'XYZ-5678']
      index = 0
      allow(FactoryBakery::RegexGeneration).to receive(:generate) do |*, **|
        value = values[index]
        index += 1
        value
      end

      first = FactoryBakery.bake!(model)
      second = FactoryBakery.bake!(model)

      expect(first.code).to eq('ABC-1234')
      expect(second.code).to eq('XYZ-5678')
      expect(first.code).not_to eq(second.code)
      expect([first, second]).to all(be_valid)
    end
  end

  describe 'PORO routing' do
    it 'honors a :without format regex on an ActiveModel-compatible target' do
      base = Class.new do
        include ActiveModel::Model
        include ActiveModel::Validations
      end
      model = define_class('WithoutFormatPoro', base) do
        attr_accessor :code

        validates :code, format: { without: /\Aadmin\z/ }
      end
      allow(FFaker::Lorem).to receive(:word).and_return('admin', 'member')

      records = 20.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:code)).to all(satisfy { |value| !value.match?(/\Aadmin\z/) })
      expect(records).to all(be_valid)
    end
  end
end
