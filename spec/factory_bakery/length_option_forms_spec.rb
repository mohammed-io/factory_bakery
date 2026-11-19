# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'length option forms (issue #45)' do
  include DefineConstantMacros

  describe 'proc bounds' do
    it 'calls a record-aware minimum proc at bake time with the object being built' do
      calls = []
      model = define_model('ProcMinLength', title: :string) do
        validates :title, length: {
          minimum: lambda { |record|
            calls << record
            5
          }
        }
      end

      expect(calls).to be_empty
      record = FactoryBakery.bake(model)

      expect(calls.length).to eq(1)
      expect(calls.first).to be_a(model)
      expect(record.title.length).to be >= 5
      expect(record).to be_valid
    end

    it 'calls a zero-arity maximum proc at bake time' do
      model = define_model('ZeroArityMaxLength', code: :string) do
        validates :code, length: { maximum: -> { 4 } }
      end

      records = 10.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:code).map(&:length)).to all(be <= 4)
      expect(records).to all(be_valid)
    end

    it 're-evaluates a proc on every call instead of freezing it at initialization' do
      calls = 0
      model = define_model('FreshLengthBound', title: :string) do
        validates :title, length: {
          minimum: lambda { |_record|
            calls += 1
            5
          }
        }
      end

      filler = FactoryBakery::AttributeFillers::StringFiller.new(model, :title)
      expect(calls).to eq(0)

      filler.call
      expect(calls).to eq(1)

      filler.call
      expect(calls).to eq(2)
    end
  end

  describe 'symbol bounds' do
    let!(:model) do
      define_model('SymbolLengthLimit', summary: :string, max_chars: :integer) do
        validates :summary, length: { maximum: :max_chars }
      end
    end

    it 'resolves the symbol against the object and fills an attribute generated later in column order' do
      records = 10.times.map { FactoryBakery.bake(model) }

      expect(records).to all(be_valid)
      records.each do |record|
        expect(record.max_chars).to be_a(Integer)
        expect(record.summary.length).to be <= record.max_chars
      end
    end

    it 'honors a call-site override for the referenced attribute' do
      record = FactoryBakery.bake(model, max_chars: 3)

      expect(record.max_chars).to eq(3)
      expect(record.summary.length).to be <= 3
      expect(record).to be_valid
    end

    it 'keeps summary shorter than body using a proc that reads the generated body' do
      articles = define_model('SummaryBodyArticle', body: :string, summary: :string) do
        validates :summary, length: { maximum: ->(record) { record.body.length } }
      end

      records = 10.times.map { FactoryBakery.bake(articles) }

      records.each do |record|
        expect(record.summary.length).to be <= record.body.length
        expect(record).to be_valid
      end
    end
  end

  describe 'dynamic bounds and format negotiation' do
    it 'keeps a regex-generated value when the resolved exact length already matches' do
      model = define_model('DynamicFormatLength', code: :string) do
        validates :code, format: { with: /\A[a-z]{8}\z/ }
        validates :code, length: { is: ->(_record) { 8 } }
      end

      records = 10.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:code)).to all(match(/\A[a-z]{8}\z/))
      expect(records).to all(be_valid)
    end

    it 'names the attribute and the dynamic length option on exhaustion' do
      model = define_model('DynamicLengthExhaustion', code: :string, max_chars: :integer) do
        validates :code, format: { with: /\A[a-z]{3}\z/ }
        validates :code, length: { is: :max_chars }
      end

      expect { FactoryBakery.bake(model, max_chars: 12) }
        .to raise_error(FactoryBakery::Error, /DynamicLengthExhaustion#code.*:max_chars.*attempts/m)
    end
  end

  describe 'resolution failures' do
    it 'wraps a raising length proc in a contextual error with the original cause' do
      model = define_model('RaisingLengthProc', title: :string) do
        validates :title, length: { minimum: ->(_record) { MissingLengthNamespace::MIN } }
      end

      expect { FactoryBakery.bake(model) }
        .to raise_error(FactoryBakery::Error, /RaisingLengthProc#title.*minimum.*MissingLengthNamespace/m) { |error|
          expect(error.cause).to be_a(NameError)
        }
    end

    it 'raises a contextual error when a bound resolves to an unusable value' do
      model = define_model('UnusableLengthValue', title: :string) do
        validates :title, length: { minimum: ->(_record) { 'not-a-number' } }
      end

      expect { FactoryBakery.bake(model) }
        .to raise_error(FactoryBakery::Error, /UnusableLengthValue#title.*minimum.*not-a-number/m)
    end

    it 'relaxes an unresolvable symbol bound instead of crashing' do
      model = define_model('MissingLengthRef', title: :string) do
        validates :title, length: { minimum: :no_such_attribute }
      end

      record = nil
      expect { record = FactoryBakery.bake(model) }.not_to raise_error
      expect(record.title).to be_a(String)
    end
  end

  describe 'literal bounds stay unchanged' do
    it 'keeps literal minimum and maximum behavior across repeated bakes' do
      model = define_model('LiteralLengthBounds', title: :string) do
        validates :title, length: { minimum: 3, maximum: 12 }
      end

      records = 20.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:title).map(&:length)).to all(be_between(3, 12).inclusive)
      expect(records).to all(be_valid)
    end
  end
end
