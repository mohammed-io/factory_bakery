# frozen_string_literal: true

require 'spec_helper'
require 'uri'

# Issue #59: semantic candidates come first from an attribute's name or its
# normalized column type. Every candidate still goes through the verifier: a
# declared format, length or inclusion/exclusion constraint always wins.
RSpec.describe 'semantic string candidates (issue #59)' do
  include DefineConstantMacros

  let(:title_pattern) { /\A[A-Z][a-z]+(?: [a-z]+){3,} \d{6}\z/ }
  let(:reserved_url_pattern) { %r{\Ahttps://(?:[\w-]+\.)?(?:example\.com|example\.test|example)/} }
  let(:ip_pattern) { /\A192\.0\.2\.(?:[1-9]|[1-9]\d|1\d\d|2[0-4]\d|25[0-4])\z/ }

  describe 'title, subject and headline' do
    it 'generates a multi-word sentence with the entropy suffix' do
      model = define_model('SemanticTitle59', title: { type: :string, null: false })
      records = Array.new(20) { FactoryBakery.bake(model) }

      expect(records.map(&:title)).to all(match(title_pattern))
      expect(records.map(&:title)).to all(satisfy { |value| value.length >= 20 })
      expect(records.map(&:title).uniq.length).to eq(20)
    end

    it 'uses the same rule for subject and headline' do
      model = define_model('SemanticHeadline59', subject: { type: :string, null: false },
                                                 headline: { type: :string, null: false })
      record = FactoryBakery.bake(model)

      expect(record.subject).to match(title_pattern)
      expect(record.headline).to match(title_pattern)
    end

    it 'passes a min-15-chars, at-least-3-distinct-words validator' do
      model = define_model('SemanticClearTitle59', title: { type: :string, null: false }) do
        validate :title_is_clear

        def title_is_clear
          words = title.to_s.split
          return if title.to_s.length >= 15 && words.uniq.length >= 3

          errors.add(:title, 'seems unclear')
        end
      end

      records = Array.new(20) { FactoryBakery.bake(model) }

      expect(records).to all(be_valid)
      expect(records.map(&:title)).to all(match(title_pattern))
    end
  end

  describe 'body-like attributes' do
    it 'generates a paragraph of several sentences for every body-like name' do
      columns = %i[body raw content description message text].to_h { |name| [name, { type: :text, null: false }] }
      model = define_model('SemanticBody59', columns)
      record = FactoryBakery.bake(model)

      columns.each_key do |name|
        value = record.public_send(name)
        expect(value.length).to be >= 60
        expect(value.scan(/\./).length).to be >= 2
      end
    end
  end

  describe 'URL-named attributes' do
    it 'generates an https URL on a reserved domain' do
      columns = %i[url website endpoint uri link payload_url].to_h { |name| [name, { type: :string, null: false }] }
      model = define_model('SemanticUrl59', columns)
      record = FactoryBakery.bake(model)

      columns.each_key do |name|
        expect(record.public_send(name)).to match(reserved_url_pattern)
      end
    end

    it 'checks plausible URL candidates against a lookahead format before synthesis' do
      model = define_model('SemanticUrlFormat59', payload_url: { type: :string, null: false }) do
        validates :payload_url, format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
      end

      records = Array.new(20) { FactoryBakery.bake(model) }

      expect(records).to all(be_valid)
      expect(records.map(&:payload_url)).to all(match(reserved_url_pattern))
    end

    it 'regenerates a reserved URL when a uniqueness constraint collides' do
      model = define_model('SemanticUrlUnique59', payload_url: { type: :string, null: false }) do
        validates :payload_url, uniqueness: true,
                                format: { with: URI::DEFAULT_PARSER.make_regexp(%w[http https]) }
      end

      records = Array.new(3) { FactoryBakery.bake!(model) }

      expect(records.map(&:payload_url).uniq.size).to eq(3)
      expect(records.map(&:payload_url)).to all(match(reserved_url_pattern))
    end

    it 'still bakes the Discourse WebHook lookahead regex' do
      regex = %r{\A(?=(?i:http|https):)[a-z]+://[^\s/]+(?:/\S*)?\z}i
      model = define_model('SemanticWebHook59', payload_url: { type: :string, null: false }) do
        validates :payload_url, format: { with: regex }
      end

      expect(FactoryBakery.bake(model)).to be_valid
    end

    it 'falls back to generation when no candidate fits the declared format' do
      model = define_model('SemanticUrlFallback59', endpoint: { type: :string, null: false }) do
        validates :endpoint, format: { with: %r{\Ahttp://[a-z]+\z} }
      end

      records = Array.new(10) { FactoryBakery.bake(model) }

      expect(records).to all(be_valid)
      expect(records.map(&:endpoint)).to all(match(%r{\Ahttp://[a-z]+\z}))
    end
  end

  describe 'filename-like attributes' do
    it 'generates a word with an image extension' do
      model = define_model('SemanticFilename59', filename: { type: :string, null: false },
                                                 file_name: { type: :string, null: false })
      record = FactoryBakery.bake(model)

      expect(record.filename).to match(/\A[a-z]+\.png\z/)
      expect(record.file_name).to match(/\A[a-z]+\.png\z/)
    end
  end

  describe 'host-like attributes' do
    it 'generates reserved example.com hosts' do
      model = define_model('SemanticHost59', host: { type: :string, null: false },
                                             hostname: { type: :string, null: false },
                                             domain: { type: :string, null: false })
      record = FactoryBakery.bake(model)

      %i[host hostname domain].each do |name|
        expect(record.public_send(name)).to match(/\A[a-z]+\.example\.com\z/)
      end
    end
  end

  describe 'name-based IP attributes on ordinary string columns' do
    it 'generates a TEST-NET-1 address for ip and ip_address' do
      model = define_model('SemanticIp59', ip: { type: :string, null: false },
                                           ip_address: { type: :string, null: false })
      record = FactoryBakery.bake(model)

      expect(record.ip).to match(ip_pattern)
      expect(record.ip_address).to match(ip_pattern)
    end

    it 'does not mistake description or zip for an ip attribute' do
      model = define_model('SemanticIpOrder59', description: { type: :text, null: false },
                                                zip: { type: :string, null: false })
      record = FactoryBakery.bake(model)

      expect(record.description.length).to be >= 60
      expect(record.zip).not_to match(ip_pattern)
    end
  end

  describe 'timezone attributes' do
    it 'generates UTC or a real IANA zone' do
      model = define_model('SemanticTimezone59', timezone: { type: :string, null: false },
                                                 time_zone: { type: :string, null: false })
      record = FactoryBakery.bake(model)

      expect([record.timezone, record.time_zone]).to all(match(%r{\A(?:UTC|[A-Za-z_]+/[A-Za-z_]+)\z}))
    end
  end

  # The PG-only examples below exercise the full bake path on PostgreSQL. This
  # one guards the normalized-type routing itself on every adapter, so the
  # column-type rules cannot silently regress on the default SQLite run.
  describe 'normalized column-type rules without a database' do
    it 'routes inet, cidr and tsvector to the string filler' do
      { inet: ip_pattern, cidr: %r{\A192\.0\.2\.0/24\z}, tsvector: /\A[a-z]+(?: [a-z]+){3,}\z/ }.each do |type, pattern|
        constraints = FactoryBakery::ConstraintSet.new(
          model_class: Object, attr_name: 'search_data', type: type,
          column_backed: true, column_backed_target: true
        )
        allow(FactoryBakery::ConstraintSet).to receive(:for).with(Object, 'search_data').and_return(constraints)
        filler = FactoryBakery::AttributeFillers::FillerSelector.new(Object, 'search_data').call

        expect(filler).to be_a(FactoryBakery::AttributeFillers::StringFiller)
        expect(filler.call).to match(pattern)
      end
    end
  end

  describe 'PostgreSQL-only column types' do
    before { skip 'native PostgreSQL types require PostgreSQL' unless DatabaseSupport.postgresql? }

    it 'fills inet and cidr columns with TEST-NET-1 values' do
      model = define_model('SemanticNetwork59', address: { type: :inet, null: false },
                                                network: { type: :cidr, null: false })
      record = FactoryBakery.bake(model)

      expect(record.address).to match(ip_pattern)
      expect(record.network).to eq('192.0.2.0/24')
    end

    it 'fills a tsvector column with lorem words when presence requires it' do
      model = define_model('SemanticSearch59', search_data: :tsvector) do
        validates :search_data, presence: true
      end

      record = FactoryBakery.bake(model)

      expect(record.search_data).to be_a(String)
      expect(record.search_data.split.length).to be >= 4
    end
  end
end
