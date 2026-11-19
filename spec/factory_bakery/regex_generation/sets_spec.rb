# frozen_string_literal: true

require 'spec_helper'
require_relative '../../support/regex_generation_matchers'

RSpec.describe 'RegexGeneration: character sets and Unicode properties' do
  include RegexGenerationHelpers

  def sample_text(regexp, **options)
    generate_samples(regexp, count: 500, **options).join
  end

  describe 'ranges and plain members' do
    it 'stays inside a range' do
      expect(/\A[a-f]{5}\z/).to generate_matching(count: 500)
      expect(sample_text(/\A[a-f]{5}\z/)).not_to match(/[^a-f]/)
    end

    it 'treats leading and trailing hyphens as members' do
      expect(/\A[-ab]+\z/).to generate_matching
      expect(/\A[ab-]+\z/).to generate_matching
    end

    it 'treats an escaped ] as a member' do
      expect(/\A[\]a]+\z/).to generate_matching
    end

    it 'treats a ] written first (unescaped) as a member' do
      regexp = Regexp.new('\A[]]{3}\z')

      expect(generate_samples(regexp, count: 10).uniq).to eq([']]]'])
    end

    it 'treats a ] written first after ^ as a member of the negated set' do
      regexp = Regexp.new('\A[^]a]{3}\z')

      expect(regexp).to generate_matching(count: 500)
      expect(sample_text(regexp)).not_to match(/[\]a]/)
    end

    it 'leaves an escaped bracket before ] alone' do
      expect(generate_samples(Regexp.new('\A\[]\z'), count: 3).uniq).to eq(['[]'])
    end

    it 'handles escapes and character types inside a set' do
      regexp = /\A[\d\s\x41\u00e9\n]+\z/

      expect(regexp).to generate_matching
    end

    it 'generates every member of a small set' do
      samples = generate_samples(/\A[abc]\z/)

      expect(samples.uniq.sort).to eq(%w[a b c])
    end
  end

  describe 'negation' do
    it 'never emits a forbidden character' do
      regexp = /\A[^@\s]+\z/

      expect(regexp).to generate_matching(count: 500)
      expect(sample_text(regexp)).not_to match(/[@\s]/)
    end

    it 'never emits a forbidden character when the remaining universe is tiny' do
      regexp = /\A[^\x20-\x7E]{3}\z/

      expect(regexp).to generate_matching(count: 500)
      expect(sample_text(regexp)).not_to match(/[\x20-\x7E]/)
    end

    it 'is empty (no value) when the set excludes every character' do
      expect(FactoryBakery::RegexGeneration.generate(/[^\x00-\u{10FFFF}]/)).to be_nil
    end
  end

  describe 'nested sets and intersection' do
    it 'unions a nested set' do
      regexp = /\A[a-c[0-2]]{6}\z/
      text = sample_text(regexp)

      expect(regexp).to generate_matching
      expect(text).to match(/[a-c]/).and match(/[0-2]/)
      expect(text).not_to match(/[^a-c0-2]/)
    end

    it 'intersects sets' do
      regexp = /\A[a-z&&[^aeiou]]{6}\z/

      expect(regexp).to generate_matching(count: 500)
      expect(sample_text(regexp)).not_to match(/[aeiou]|[^a-z]/)
    end

    it 'chains intersections' do
      regexp = /\A[a-z&&a-m&&[^aeiou]]{6}\z/

      expect(regexp).to generate_matching(count: 500)
      expect(sample_text(regexp)).not_to match(/[aeiou]|[^a-m]/)
    end

    it 'yields no value for an empty intersection' do
      expect(FactoryBakery::RegexGeneration.generate(/[a&&b]/)).to be_nil
    end
  end

  describe 'POSIX classes' do
    it 'generates [[:alpha:]]' do
      expect(/\A[[:alpha:]]{5}\z/).to generate_matching(count: 500)
    end

    it 'never emits a member of a negated POSIX class [[:^digit:]]' do
      regexp = /\A[[:^digit:]]{5}\z/

      expect(regexp).to generate_matching(count: 500)
      expect(sample_text(regexp)).not_to match(/\d/)
    end

    it 'generates punctuation from [[:punct:]]' do
      expect(/\A[[:punct:]]{4}\z/).to generate_matching(count: 500)
    end
  end

  describe 'case-insensitive sets' do
    it 'produces both cases of the set' do
      text = sample_text(/\A[a-c]{6}\z/i)

      expect(text).to match(/[a-c]/).and match(/[A-C]/)
    end
  end

  describe 'characters outside printable ASCII' do
    it 'samples a range of non-ASCII letters' do
      regexp = /\A[а-я]{4}\z/

      expect(regexp).to generate_matching
    end

    it 'samples control characters' do
      expect(/\A[\r\n]{3}\z/).to generate_matching
    end

    it 'samples an explicitly named non-ASCII member' do
      expect(generate_samples(/\A[éà]\z/, count: 50).uniq.sort).to eq(%w[à é])
    end

    it 'samples a set made only of high bytes in a binary regexp' do
      regexp = binary_regexp('\A[\xE1-\xE3]{3}\z')
      values = generate_samples(regexp, count: 50)

      expect(values).to all(match(regexp))
      expect(values.map(&:encoding).uniq).to eq([Encoding::BINARY])
    end
  end

  describe 'Unicode properties' do
    {
      '\p{L}' => [/\A\p{L}{4}\z/, /\P{L}/],
      '\p{Lu}' => [/\A\p{Lu}{4}\z/, /\P{Lu}/],
      '\p{Alpha}' => [/\A\p{Alpha}{4}\z/, /\P{Alpha}/],
      '\p{Digit}' => [/\A\p{Digit}{4}\z/, /\P{Digit}/],
      '\p{Greek}' => [/\A\p{Greek}{4}\z/, /\P{Greek}/],
      '\P{Lu}' => [/\A\P{Lu}{4}\z/, /\p{Lu}/],
      '\p{^Lu}' => [/\A\p{^Lu}{4}\z/, /\p{Lu}/],
      '\p{Han}' => [/\A\p{Han}{4}\z/, /\P{Han}/],
      '\p{Ethiopic} (a script outside the curated samples)' => [/\A\p{Ethiopic}{2}\z/, /\P{Ethiopic}/]
    }.each do |name, (regexp, forbidden)|
      it "generates only #{name} characters" do
        expect(regexp).to generate_matching(count: 500)
        expect(sample_text(regexp)).not_to match(forbidden)
      end
    end

    it 'accepts a property inside a set' do
      expect(/\A[\p{Lu}\p{Nd}]{6}\z/).to generate_matching(count: 500)
    end
  end
end
