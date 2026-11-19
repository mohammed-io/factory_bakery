# frozen_string_literal: true

require 'spec_helper'

# Regressions found in the full-diff review of issues #48-#65.
RSpec.describe 'review fixes' do
  include DefineConstantMacros

  describe 'small integer ranges (finding 1)' do
    it 'bakes an odd single-value range' do
      model = define_model('OddSingleRange', n: { type: :integer, null: false }) do
        validates :n, numericality: { in: 3..3 }
      end

      expect(FactoryBakery.bake(model).n).to eq(3)
    end

    it 'bakes an exclusive range whose only survivor is odd' do
      model = define_model('OddExclusiveRange', n: { type: :integer, null: false }) do
        validates :n, numericality: { in: 3...4 }
      end

      expect(FactoryBakery.bake(model).n).to eq(3)
    end

    it 'produces both odd and even values across a small window' do
      model = define_model('MixedSmallRange', n: { type: :integer, null: false }) do
        validates :n, numericality: { in: 5..7 }
      end

      values = 60.times.map { FactoryBakery.bake(model).n }.uniq

      expect(values).to contain_exactly(5, 6, 7)
    end

    it 'still honours an explicit parity rule' do
      model = define_model('OddOnlySmallRange', n: { type: :integer, null: false }) do
        validates :n, numericality: { in: 4..9, odd: true }
      end

      expect(20.times.map { FactoryBakery.bake(model).n }).to all(be_odd)
    end
  end

  describe 'private condition predicates (finding 6)' do
    it 'evaluates a private Symbol condition like Rails does' do
      model = define_model('PrivateConditionCode', code: { type: :string, null: false }, flag: :boolean) do
        validates :code, format: { with: /\A[a-z]{5}\z/ }, if: :flag_on?
        validates :code, format: { with: /\A[0-9]{5}\z/ }, unless: :flag_on?

        private

        def flag_on?
          flag == true
        end
      end

      expect(FactoryBakery.bake(model, flag: true)).to be_valid
      expect(FactoryBakery.bake(model, flag: false)).to be_valid
    end

    it 'runs a one-argument Proc condition against the record' do
      model = define_model('ArityOneConditionCode', code: { type: :string, null: false }, flag: :boolean) do
        validates :code, format: { with: /\A[a-z]{5}\z/ }, if: ->(record) { record.flag && flag }
        validates :code, format: { with: /\A[0-9]{5}\z/ }, unless: ->(record) { record.flag && flag }
      end

      expect(FactoryBakery.bake(model, flag: true)).to be_valid
      expect(FactoryBakery.bake(model, flag: false)).to be_valid
    end
  end

  describe 'global fill_optional (finding 10)' do
    after { FactoryBakery::FillOptional.reset! }

    it 'accepts a list of symbols like the per-call option' do
      model = define_model('GlobalListOptional', title: { type: :string, null: false }, extra: :string)

      FactoryBakery.fill_optional = %i[extra]

      expect(FactoryBakery.bake(model).extra).to be_a(String)
    end

    it 'rejects a value that is not true, false or a list' do
      expect { FactoryBakery.fill_optional = 'true' }.to raise_error(ArgumentError, /fill_optional/)
    end
  end

  describe 'body-like names (finding 13)' do
    it 'does not generate paragraphs for metadata columns that mention a body word' do
      model = define_model('BodyMetadataNames', content_type: { type: :string, null: false },
                                                message_id: { type: :string, null: false },
                                                body: { type: :text, null: false })

      record = FactoryBakery.bake(model)

      expect(record.content_type.length).to be < 40
      expect(record.message_id.length).to be < 40
      expect(record.body.length).to be >= 60
    end
  end
end
