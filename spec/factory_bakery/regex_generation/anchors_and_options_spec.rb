# frozen_string_literal: true

require 'spec_helper'
require_relative '../../support/regex_generation_matchers'

RSpec.describe 'RegexGeneration: anchors and options' do
  include RegexGenerationHelpers

  def generate(regexp, **options)
    FactoryBakery::RegexGeneration.generate(regexp, **options)
  end

  describe 'anchors' do
    {
      '\A and \z' => [/\Afoo\z/, 'foo'],
      '\Z' => [/\Afoo\Z/, 'foo'],
      '^ and $' => [/^foo$/, 'foo'],
      '\G' => [/\Gfoo/, 'foo'],
      '\K (keep)' => [/foo\Kbar/, 'foobar']
    }.each do |name, (regexp, expected)|
      it "treats #{name} as zero width" do
        expect(generate(regexp)).to eq(expected)
      end
    end

    describe '\b' do
      it 'is satisfied between a word and a non-word character' do
        expect(/\bfoo\b/).to generate_matching(count: 20)
      end

      it 'makes the character after a word require a non-word character' do
        samples = generate_samples(/foo\b.+/, count: 500)

        expect(samples).to all(match(/\Afoo\W/))
      end

      it 'makes the character after a non-word character require a word character' do
        samples = generate_samples(/-\b.+/, count: 500)

        expect(samples).to all(match(/\A-\w/))
      end

      it 'requires a word character at the start of the string' do
        expect(generate_samples(/\b./, count: 500)).to all(match(/\A\w/))
      end

      it 'also constrains a character type that has word and non-word members' do
        expect(generate_samples(/a\b\S/, count: 200)).to all(match(/\Aa\W/))
      end
    end

    describe '\B' do
      it 'makes the character after a word character a word character' do
        expect(generate_samples(/a\B.+/, count: 500)).to all(match(/\Aa\w/))
      end

      it 'makes the character after a non-word character a non-word character' do
        expect(generate_samples(/-\B.+/, count: 500)).to all(match(/\A-\W/))
      end
    end

    it 'yields no value when a boundary cannot be satisfied by any candidate' do
      expect(generate(/\Aa\b\w\z/)).to be_nil
      expect(generate(/\Aa\B\W\z/)).to be_nil
    end
  end

  describe 'options' do
    it 'randomizes the case of letters under /i' do
      samples = generate_samples(/\Aabc\z/i, count: 200)

      expect(samples).to all(match(/\Aabc\z/i))
      expect(samples).to include('abc', 'ABC')
      expect(samples.uniq.size).to be > 4
    end

    it 'does not randomize case without /i' do
      expect(generate_samples(/\Aabc\z/, count: 50).uniq).to eq(['abc'])
    end

    it 'ignores whitespace and comments under /x' do
      regexp = /
        \A a b   # letters
        \d{2}    # digits
        \z
      /x

      expect(regexp).to generate_matching
      expect(generate_samples(regexp, count: 20)).to all(match(/\Aab\d{2}\z/))
    end

    it 'applies an inline (?i) to what follows it' do
      samples = generate_samples(/\Aa(?i)b\z/, count: 200)

      expect(samples).to all(match(/\Aa[bB]\z/))
      expect(samples).to include('aB')
    end

    it 'applies a scoped (?i:...) only inside the group' do
      samples = generate_samples(/\A(?i:a)b\z/, count: 200)

      expect(samples).to all(match(/\A[aA]b\z/))
      expect(samples).to include('Ab')
    end

    it 'applies (?-i:...) inside a case-insensitive regexp' do
      samples = generate_samples(/\A(?-i:a)b\z/i, count: 200)

      expect(samples).to all(match(/\Aa[bB]\z/))
    end

    it 'combines flag letters in (?mix)' do
      regexp = /(?mix) a . b /

      expect(regexp).to generate_matching
    end

    it 'turns a flag back off with (?-i)' do
      samples = generate_samples(/\A(?i)a(?-i)b\z/, count: 200)

      expect(samples).to all(match(/\A[aA]b\z/))
    end
  end
end
