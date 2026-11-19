# frozen_string_literal: true

require 'spec_helper'
require 'active_model'
require 'uri'

# Issue #65: format regexes are generated from the regexp_parser syntax tree
# (FactoryBakery::RegexGeneration), so common real-world formats bake valid
# records through the public API.
RSpec.describe 'baking format-validated attributes with regex generation (issue #65)' do
  include DefineConstantMacros

  describe 'the common email format /\A[^@\s]+@[^@\s]+\z/' do
    let!(:model) do
      define_model('RegexEmailContact', email: :string) do
        validates :email, format: { with: /\A[^@\s]+@[^@\s]+\z/ }
      end
    end

    it 'bakes valid records, never emitting a forbidden character' do
      records = 100.times.map { FactoryBakery.bake(model) }

      expect(records).to all(be_valid)
      expect(records.map(&:email)).to all(match(/\A[^@\s]+@[^@\s]+\z/))
      expect(records.map(&:email).uniq.size).to be > 50
    end
  end

  describe 'the Discourse WebHook URI regexp (leading lookahead)' do
    let!(:model) do
      define_model('RegexWebHook', payload_url: :string) do
        validates :payload_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
      end
    end

    it 'bakes valid records whose URL starts with the lookahead text' do
      records = 50.times.map { FactoryBakery.bake(model) }

      expect(records).to all(be_valid)
      expect(records.map(&:payload_url)).to all(match(/\Ahttps?:/i))
    end
  end

  describe 'format together with length constraints' do
    it 'aims the generated value at an exact length' do
      model = define_model('RegexExactLength', code: :string) do
        validates :code, format: { with: /\A[a-z0-9]+\z/ }
        validates :code, length: { is: 12 }
      end

      records = 20.times.map { FactoryBakery.bake(model) }

      expect(records.map { |record| record.code.length }.uniq).to eq([12])
      expect(records).to all(be_valid)
    end

    it 'aims the generated value at a length range' do
      model = define_model('RegexRangedLength', code: :string) do
        validates :code, format: { with: /\A\w+\z/ }
        validates :code, length: { in: 15..20 }
      end

      records = 20.times.map { FactoryBakery.bake(model) }

      expect(records.map { |record| record.code.length }).to all(be_between(15, 20))
      expect(records).to all(be_valid)
    end

    it 'keeps an unbounded format within the database limit' do
      model = define_model('RegexLimitedCode', short_code: { type: :string, limit: 5 }) do
        validates :short_code, format: { with: /\A[a-z]+\z/ }
      end

      records = 20.times.map { FactoryBakery.bake(model) }

      expect(records.map { |record| record.short_code.length }).to all(be_between(1, 5))
      expect(records).to all(be_valid)
    end
  end

  describe 'ActiveModel-compatible objects' do
    it 'generates format-valid values for a PORO' do
      base = Class.new do
        include ActiveModel::Model
        include ActiveModel::Validations
      end
      model = define_class('RegexFormatPoro', base) do
        attr_accessor :handle

        validates :handle, format: { with: /\A@[a-z0-9_]{3,15}\z/ }
      end

      records = 20.times.map { FactoryBakery.bake(model) }

      expect(records).to all(be_valid)
    end
  end
end
