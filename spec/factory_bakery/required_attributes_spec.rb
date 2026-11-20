# frozen_string_literal: true

require 'spec_helper'
require 'active_model'

# Issue #51: by default a bake fills only the attributes a valid record needs.
# Optional columns keep their database default or nil; the opt-in and the
# verified fallback restore the old behaviour where it is actually needed.
RSpec.describe 'required-only baking (issue #51)' do
  include DefineConstantMacros

  after { FactoryBakery.fill_optional = false }

  describe 'the default rule' do
    it 'leaves a nullable unvalidated column nil and keeps a database default' do
      model = define_model('LeanRecord',
                           required: :string,
                           optional: :string,
                           state: { type: :string, default: 'draft' }) do
        validates :required, presence: true
      end

      record = FactoryBakery.bake(model)

      expect(record.required).to be_present
      expect(record.optional).to be_nil
      expect(record.state).to eq('draft')
      expect(record).to be_valid
    end

    it 'fills a NOT NULL column without a default' do
      model = define_model('LeanNotNull', required: { type: :string, null: false })

      expect(FactoryBakery.bake(model).required).to be_present
    end

    it 'fills nullable columns whose validators reject nil' do
      model = define_model('LeanValidated',
                           present: :string,
                           included: :string,
                           formatted: :string,
                           numbered: :integer,
                           terms_accepted: :string,
                           minimum: :string) do
        validates :present, presence: true
        validates :included, inclusion: { in: %w[pending done] }
        validates :formatted, format: { with: /\A[a-z]+\z/ }
        validates :numbered, numericality: { only_integer: true, greater_than: 3 }
        validates :terms_accepted, acceptance: { accept: 'yes', allow_nil: false }
        validates :minimum, length: { minimum: 2 }
      end

      record = FactoryBakery.bake(model)

      expect(record.present).to be_present
      expect(%w[pending done]).to include(record.included)
      expect(record.formatted).to match(/\A[a-z]+\z/)
      expect(record.numbered).to be > 3
      expect(record.terms_accepted).to eq('yes')
      expect(record.minimum.length).to be >= 2
      expect(record).to be_valid
    end

    it 'leaves nullable columns alone when validators allow nil or do not reject it' do
      model = define_model('LeanRelaxed',
                           allowed_nil: :string,
                           allowed_blank: :string,
                           maximum_only: :string) do
        validates :allowed_nil, inclusion: { in: %w[a b] }, allow_nil: true
        validates :allowed_blank, format: { with: /\A[a-z]+\z/ }, allow_blank: true
        validates :maximum_only, length: { maximum: 4 }
      end

      record = FactoryBakery.bake(model)

      expect([record.allowed_nil, record.allowed_blank, record.maximum_only]).to all(be_nil)
      expect(record).to be_valid
    end

    it 'does not force filling for a custom EachValidator that tolerates nil' do
      url_validator = Class.new(ActiveModel::EachValidator) do
        def validate_each(record, attribute, value)
          return if value.nil?

          record.errors.add(attribute, 'is not a URL') unless value.to_s.start_with?('http')
        end
      end
      stub_const('UrlValidator', url_validator)

      model = define_model('LeanCustomValidator', custom: :string) do
        validates :custom, url: true
      end

      record = FactoryBakery.bake(model)

      expect(record.custom).to be_nil
      expect(record).to be_valid
    end

    it 'fills a blank default that a presence validator requires, including false on a boolean' do
      model = define_model('LeanBlankDefault',
                           status: { type: :string, default: '' },
                           flag: { type: :boolean, default: false }) do
        validates :status, presence: true
        validates :flag, presence: true
      end

      record = FactoryBakery.bake(model)

      expect(record.status).to be_present
      expect(record.flag).to be(true)
      expect(record).to be_valid
    end

    it 'never calls the setter of an optional column' do
      model = define_model('LeanNoSetter', required: :string, optional: :string) do
        validates :required, presence: true

        def optional=(_value)
          raise 'optional setter must not be called'
        end
      end

      record = FactoryBakery.bake(model)

      expect(record.required).to be_present
      expect(record).to be_valid
    end

    it 'keeps validator-declared virtual attributes unchanged' do
      base = Class.new do
        include ActiveModel::Model
        include ActiveModel::Validations
      end
      model = define_class('LeanVirtual', base) do
        attr_accessor :name

        validates :name, presence: true
      end

      expect(FactoryBakery.bake(model).name).to be_present
    end
  end

  describe 'fill_optional opt-in' do
    let!(:model) do
      define_model('OptInRecord', required: :string, optional: :string, state: { type: :string, default: 'draft' }) do
        validates :required, presence: true
      end
    end

    it 'restores filling of optional columns for one call' do
      record = FactoryBakery.bake(model, fill_optional: true)

      expect(record.required).to be_present
      expect(record.optional).to be_present
      expect(record.state).to eq('draft')
    end

    it 'accepts a list of attribute names' do
      record = FactoryBakery.bake(model, fill_optional: [:optional])

      expect(record.optional).to be_present
      expect(record.state).to eq('draft')
    end

    it 'applies a process-wide setting from configure' do
      FactoryBakery.configure { |config| config.fill_optional = true }

      expect(FactoryBakery.bake(model).optional).to be_present
    end

    it 'lets a call opt out of a process-wide setting' do
      FactoryBakery.configure { |config| config.fill_optional = true }

      expect(FactoryBakery.bake(model, fill_optional: false).optional).to be_nil
    end

    it 'rejects an unsupported value' do
      expect { FactoryBakery.bake(model, fill_optional: 'yes') }.to raise_error(ArgumentError, /fill_optional/)
    end
  end

  describe 'verified fallback' do
    let(:credential_validator) do
      Class.new(ActiveModel::Validator) do
        def validate(record)
          return unless record.token.nil? && record.secret.nil?

          record.errors.add(:base, 'a credential must be selected')
        end
      end
    end

    it 'rebuilds with optional columns filled when a custom validator needs one' do
      validator = credential_validator
      model = define_model('FallbackCredential', token: :string, secret: :string) do
        validates_with validator
      end

      record = FactoryBakery.bake(model)

      expect([record.token, record.secret]).to all(be_present)
      expect(record).to be_valid
    end

    it 'does not fall back when the caller supplied every optional column' do
      validations = 0
      validator = Class.new(ActiveModel::Validator) do
        define_method(:validate) do |record|
          validations += 1
          record.errors.add(:base, 'missing') if record.token.nil? && record.secret.nil?
        end
      end
      model = define_model('NoFallbackCredential', token: :string, secret: :string) do
        validates_with validator
      end

      record = FactoryBakery.bake(model, token: 'given-token', secret: 'given-secret')

      expect([record.token, record.secret]).to eq(%w[given-token given-secret])
      expect(validations).to eq(0)
    end

    it 'runs the fallback once for a nested parent' do
      validations = 0
      validator = Class.new(ActiveModel::Validator) do
        define_method(:validate) do |record|
          validations += 1
          record.errors.add(:base, 'missing') if record.token.nil? && record.secret.nil?
        end
      end
      child = define_model('FallbackChild', token: :string, secret: :string) do
        validates_with validator
      end
      parent = define_model('FallbackParent', name: :string) do
        attr_accessor :child

        validates :name, presence: true
      end
      FactoryBakery.define(parent) { child { FactoryBakery.bake(child) } }

      record = FactoryBakery.bake(parent)

      expect(record.child).to be_a(child)
      expect(validations).to eq(1)
      expect(record.child).to be_valid
    end

    it 'returns the required-only result when it is valid and never fills optional columns' do
      model = define_model('ValidLean', required: :string, optional: :string) do
        validates :required, presence: true
      end

      record = FactoryBakery.bake(model)

      expect(record.required).to be_present
      expect(record.optional).to be_nil
    end
  end

  # A column guarded only by app validation can receive a value the
  # heuristics cannot know is wrong. An optional fill that carries an error is
  # put back to its column default when that makes the record valid; a required
  # column keeps its value.
  describe 'optional fills that app validation rejects' do
    it 'puts an optional fill back to nil when a validate block rejects it' do
      model = define_model('OptInCustomValidated', name: :string, languages: :string) do
        validates :name, presence: true
        validate { errors.add(:languages, :invalid) if languages.present? && languages != 'en' }
      end
      allow(FFaker::Lorem).to receive(:word).and_return('ruby')

      record = FactoryBakery.bake(model, fill_optional: true)

      expect(record.languages).to be_nil
      expect(record.name).to be_present
      expect(record).to be_valid
    end

    it 'puts an optional fill back when a custom EachValidator rejects it' do
      validator = Class.new(ActiveModel::EachValidator) do
        def validate_each(record, attribute, value)
          return if value.nil?

          record.errors.add(attribute, :invalid) unless value == 'en'
        end
      end
      stub_const('LanguageValidator', validator)
      model = define_model('OptInEachValidated', name: :string, languages: :string) do
        validates :name, presence: true
        validates :languages, language: true
      end
      allow(FFaker::Lorem).to receive(:word).and_return('ruby')

      record = FactoryBakery.bake(model, fill_optional: true)

      expect(record.languages).to be_nil
      expect(record.name).to be_present
      expect(record).to be_valid
    end

    it 'puts an optional fill back to its column default when the column has one' do
      model = define_model('OptInDefaulted', name: :string, languages: { type: :string, default: 'en' }) do
        validates :name, presence: true
        # The length rule is what makes the heuristics fill a defaulted column
        # (issue #41); the validate block is what rejects the fill.
        validates :languages, length: { maximum: 20 }
        validate { errors.add(:languages, :invalid) if languages.present? && languages != 'en' }
      end
      allow(FFaker::Lorem).to receive(:word).and_return('ruby')

      record = FactoryBakery.bake(model, fill_optional: true)

      expect(record.languages).to eq('en')
      expect(record).to be_valid
    end

    it 'keeps the generated value when neither it nor the default is accepted' do
      model = define_model('OptInUnfixable', name: :string, languages: { type: :string, default: 'fr' }) do
        validates :name, presence: true
        validates :languages, length: { maximum: 20 }
        validate { errors.add(:languages, :invalid) if languages.present? && languages != 'en' }
      end
      allow(FFaker::Lorem).to receive(:word).and_return('ruby')

      record = FactoryBakery.bake(model, fill_optional: true)

      expect(record.languages).to eq('ruby')
      expect(record).not_to be_valid
    end
  end
end
