# frozen_string_literal: true

require 'spec_helper'
require 'uri'
require_relative '../../support/regex_generation_matchers'

RSpec.describe 'RegexGeneration: lookaround and the absence operator' do
  include RegexGenerationHelpers

  def generate(regexp, **options)
    FactoryBakery::RegexGeneration.generate(regexp, **options)
  end

  describe 'positive lookahead' do
    it 'generates the lookahead body first and continues from it at the start of a sequence' do
      regexp = %r{\A(?=(?i:http|https):)[a-z]+://\w+\z}i
      samples = generate_samples(regexp, count: 200)

      expect(samples).to all(match(%r{\Ahttps?://}i))
      expect(samples.map { |sample| sample[/\Ahttps?/i].downcase }.uniq.sort).to eq(%w[http https])
    end

    it 'generates valid URIs for the Discourse WebHook URI regexp' do
      regexp = URI::DEFAULT_PARSER.make_regexp(%w[http https])

      expect(regexp).to generate_matching(count: 200)
      expect(generate_samples(regexp, count: 200)).to all(match(/\Ahttps?:/i))
    end

    it 'follows the text through a literal after it' do
      expect(generate_samples(/\A(?=abc)abc\z/, count: 5).uniq).to eq(['abc'])
    end

    it 'follows the text case-insensitively through a literal under /i' do
      samples = generate_samples(/\A(?=aB)ab\z/i, count: 100)

      expect(samples).to all(match(/\Aab\z/i))
    end

    it 'repeats a character class exactly as long as the pending text it accepts' do
      samples = generate_samples(/\A(?=abc1)[a-z]*\d\z/, count: 100)

      expect(samples.uniq).to eq(['abc1'])
    end

    it 'appends the text still pending at the end' do
      expect(generate_samples(/foo(?=bar)/, count: 5).uniq).to eq(['foobar'])
    end

    it 'stops following the text once the next element disagrees with it' do
      expect(/\A(?=a)b?\z|\A(?=a)a?/).to generate_matching(count: 100)
    end

    it 'lets a later lookahead replace the pending text' do
      expect(/\A(?=a)(?=ab)ab\z/).to generate_matching(count: 20)
    end

    it 'yields no value when the lookahead cannot be satisfied' do
      expect(generate(/\Afoo(?=bar)\z/)).to be_nil
    end
  end

  describe 'negative lookahead' do
    it 'generates the main path and keeps only candidates that pass verification' do
      regexp = /\A(?!admin)[a-z]{5}\z/

      expect(regexp).to generate_matching(count: 500)
    end

    it 'yields no value for an unsatisfiable negative lookahead' do
      expect(generate(/\A(?!a)a\z/)).to be_nil
    end
  end

  describe 'lookbehind' do
    it 'emits the lookbehind text when nothing precedes it' do
      samples = generate_samples(/(?<=\$)\d+/, count: 100)

      expect(samples).to all(match(/\A\$\d+\z/))
    end

    it 'is satisfied by preceding output' do
      expect(generate_samples(/foo(?<=o)bar/, count: 5).uniq).to eq(['foobar'])
    end

    it 'keeps preceding output that already satisfies a positive lookbehind' do
      expect(generate_samples(/a(?<=a)b/, count: 5).uniq).to eq(['ab'])
    end

    it 'handles a negative lookbehind by verification' do
      expect(/(?<!a)b/).to generate_matching(count: 100)
    end

    it 'yields no value for an unsatisfiable lookbehind' do
      expect(generate(/\Aa(?<=b)\z/)).to be_nil
    end
  end

  describe 'absence operator' do
    it 'generates text that does not contain the body' do
      regexp = /\A(?~foo)\z/
      samples = generate_samples(regexp, count: 300)

      expect(samples).to all(match(regexp))
      expect(samples).to all(satisfy { |sample| !sample.include?('foo') })
      expect(samples.map(&:length).uniq.size).to be > 3
    end

    it 'avoids a body that is a character class' do
      regexp = /\A(?~\d)\z/

      expect(generate_samples(regexp, count: 300)).to all(satisfy { |sample| !sample.match?(/\d/) })
    end

    it 'generates between the surrounding text' do
      expect(%r{\A/\*(?~\*/)\*/\z}).to generate_matching(count: 300)
    end

    it 'respects the length hints' do
      samples = generate_samples(/\A(?~x)\z/, count: 100, min_length: 4, max_length: 4)

      expect(samples.map(&:length).uniq).to eq([4])
    end

    it 'caps the filler length even when a larger minimum is requested' do
      expect(generate(/(?~x)/, min_length: 100)).to be_nil
    end

    it 'yields no value when nothing of the requested length can avoid the body' do
      expect(generate(/\A(?~.)\z/, min_length: 3)).to be_nil
    end
  end
end
