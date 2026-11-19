# frozen_string_literal: true

require 'spec_helper'
require_relative '../../support/regex_generation_matchers'

RSpec.describe FactoryBakery::RegexGeneration do
  include RegexGenerationHelpers

  def generate(regexp, **options)
    described_class.generate(regexp, **options)
  end

  describe '.generate' do
    it 'returns a String the regexp matches' do
      value = generate(/\A[a-z]+-\d+\z/)

      expect(value).to be_a(String).and match(/\A[a-z]+-\d+\z/)
    end

    it 'returns nil for anything that is not a Regexp' do
      expect(generate('\A[a-z]+\z')).to be_nil
      expect(generate(nil)).to be_nil
    end

    it 'returns nil for a regexp no string can match' do
      expect(generate(/\Afoo(?=bar)\z/)).to be_nil
      expect(generate(/a\bb/)).to be_nil
    end

    it 'returns nil, never raises, when the regexp cannot be parsed' do
      allow(Regexp::Parser).to receive(:parse).and_raise(Regexp::Parser::Error, 'unsupported syntax')

      expect(generate(/uncached-unparseable-#{rand(1_000_000)}/)).to be_nil
    end

    it 'returns nil, never raises, when the random source fails' do
      broken = Object.new
      def broken.rand(*)
        raise 'entropy exhausted'
      end

      expect(generate(/\A[a-z]+\z/, random: broken)).to be_nil
    end
  end

  describe 'random source' do
    it 'is deterministic for a seeded Random' do
      first = generate(/\A\w{8}-\d{4}\z/, random: Random.new(7))
      second = generate(/\A\w{8}-\d{4}\z/, random: Random.new(7))
      other = generate(/\A\w{8}-\d{4}\z/, random: Random.new(8))

      expect(first).to eq(second)
      expect(first).not_to eq(other)
    end

    it 'defaults to Kernel global randomness, so srand makes results repeatable' do
      srand(42)
      first = generate(/\A\w{8}\z/)
      srand(42)
      second = generate(/\A\w{8}\z/)

      expect(first).to eq(second)
    end

    it 'accepts any object that responds to rand(Integer)' do
      zeros = Object.new
      def zeros.rand(*)
        0
      end

      expect(generate(/\A[a-z]{3}\z/, random: zeros)).to eq('aaa')
    end
  end

  describe 'bounds' do
    it 'abandons a candidate longer than the output bound' do
      expect(generate(/\A[a-z]{257}\z/)).to be_nil
      expect(generate(/\A[a-z]{256}\z/)).to match(/\A[a-z]{256}\z/)
    end

    it 'abandons a candidate nested deeper than the depth bound' do
      deep = Regexp.new("#{'(?:' * 70}a#{')' * 70}")

      expect(generate(deep)).to be_nil
      expect(generate(Regexp.new("#{'(?:' * 30}a#{')' * 30}"))).to eq('a')
    end

    it 'abandons a candidate that needs more steps than the step bound' do
      explosion = /(?:(?:(?:(?:){9}){9}){9}){9}x/

      expect(generate(explosion)).to be_nil
    end

    it 'stays bounded for an enormous repetition count' do
      expect(generate(/\Aa{100000}\z/)).to be_nil
      expect(generate(/\A(?:){100000}x\z/)).to be_nil
    end

    it 'stays bounded for an enormous minimum-length hint' do
      expect(generate(/\A[a-z]*\z/, min_length: 1_000_000_000)).to be_nil
    end
  end

  describe 'length hints' do
    it 'returns a value within the hints' do
      expect(generate_samples(/\A\h{3}|\h{6}\z/, count: 50, max_length: 3).map(&:length).uniq).to eq([3])
      expect(generate_samples(/\A\h{3}|\h{6}\z/, count: 50, min_length: 4).map(&:length).uniq).to eq([6])
    end

    it 'treats nil hints as no constraint' do
      expect(generate(/\A[a-z]+\z/, min_length: nil, max_length: nil)).to match(/\A[a-z]+\z/)
    end
  end

  describe 'parse cache' do
    it 'parses each regexp once' do
      regexp = /\A[a-z]{3}-cache-#{rand(1_000_000)}\z/
      allow(Regexp::Parser).to receive(:parse).and_call_original

      5.times { generate(regexp) }

      expect(Regexp::Parser).to have_received(:parse).once
    end

    it 'shares the parse between equal regexps' do
      source = "\\Ashared-#{rand(1_000_000)}\\z"
      allow(Regexp::Parser).to receive(:parse).and_call_original

      generate(Regexp.new(source))
      generate(Regexp.new(source))

      expect(Regexp::Parser).to have_received(:parse).once
    end

    context 'with a small cache' do
      around do |example|
        cache = FactoryBakery::RegexGeneration::TreeCache
        original = cache.instance_variable_get(:@entries)
        cache.instance_variable_set(:@entries, {})
        example.run
      ensure
        cache.instance_variable_set(:@entries, original)
      end

      before { stub_const('FactoryBakery::RegexGeneration::Limits::MAX_CACHED_REGEXPS', 2) }

      it 'is bounded: the oldest entry is evicted first' do
        first, second, third = Array.new(3) { |index| Regexp.new("\\Abounded-#{rand(1_000_000)}-#{index}\\z") }
        allow(Regexp::Parser).to receive(:parse).and_call_original

        [first, second, third, second, first].each { |regexp| generate(regexp) }

        # first, second, third parse; second is still cached; first was evicted
        expect(Regexp::Parser).to have_received(:parse).exactly(4).times
      end
    end

    it 'serves concurrent generations of the same regexp' do
      regexp = /\A(?<a>\w{3})-\k<a>-\d{2,4}\z/

      results = Array.new(8) { Thread.new { Array.new(50) { generate(regexp) } } }.flat_map(&:value)

      expect(results).to all(match(regexp))
    end
  end

  describe 'binary regexps' do
    it 'generates a binary String for non-ASCII bytes' do
      regexp = binary_regexp('\A[\xE1-\xFF]{3}\z')
      value = generate(regexp)

      expect(value.encoding).to eq(Encoding::BINARY)
      expect(value).to match(regexp)
    end

    it 'handles sets with printable members in a binary regexp' do
      expect(binary_regexp('\A[a-c\xE1]{4}\z')).to generate_matching
    end
  end
end
