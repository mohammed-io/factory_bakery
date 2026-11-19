# frozen_string_literal: true

require 'spec_helper'
require_relative '../../support/regex_generation_matchers'

RSpec.describe 'RegexGeneration: groups, alternation and quantifiers' do
  include RegexGenerationHelpers

  def generate(regexp, **options)
    FactoryBakery::RegexGeneration.generate(regexp, **options)
  end

  def lengths(regexp, **options)
    generate_samples(regexp, count: 300, **options).map(&:length)
  end

  describe 'groups' do
    {
      'capturing' => /\A(ab)c\z/,
      'non-capturing' => /\A(?:ab)c\z/,
      'named (?<n>)' => /\A(?<n>ab)c\z/,
      "named (?'n')" => /\A(?'n'ab)c\z/,
      'atomic' => /\A(?>ab)c\z/,
      'with a comment (?#...)' => /\Aab(?#nothing to see)c\z/,
      'with an options group' => /\A(?i:ab)c\z/i
    }.each do |name, regexp|
      it "generates through a #{name} group" do
        expect(generate_samples(regexp, count: 20)).to all(match(/\Aabc\z/i))
      end
    end

    it 'repeats a group' do
      expect(/\A(?:ab){3}\z/).to generate_matching(count: 20)
      expect(generate(/\A(?:ab){3}\z/)).to eq('ababab')
    end

    it 'repeats a capturing group' do
      expect(generate_samples(/\A(\d\d){2}\z/, count: 20)).to all(match(/\A\d{4}\z/))
    end
  end

  describe 'alternation' do
    it 'chooses uniformly among the branches' do
      samples = generate_samples(/\A(?:red|green|blue)\z/, count: 300)

      expect(samples.tally.keys.sort).to eq(%w[blue green red])
      expect(samples.tally.values).to all(be > 60)
    end

    it 'supports top-level alternation' do
      expect(generate_samples(/\Aab|cd\z/, count: 100).uniq.sort).to eq(%w[ab cd])
    end

    it 'supports an empty branch' do
      expect(generate_samples(/\Aa(?:b|)\z/, count: 100).uniq.sort).to eq(%w[a ab])
    end

    it 'prefers branches that fit the length hints' do
      samples = generate_samples(/\A(?:a|bbbb)\z/, count: 50, min_length: 3)

      expect(samples.uniq).to eq(['bbbb'])
    end

    it 'falls back to any branch when none fits, leaving verification to reject it' do
      expect(generate(/\A(?:a|bb)\z/, min_length: 5)).to be_nil
    end
  end

  describe 'quantifiers' do
    it '? repeats zero or one time' do
      expect(lengths(/\Aa?\z/).uniq.sort).to eq([0, 1])
    end

    it '* repeats zero up to the default maximum of 8' do
      values = lengths(/\Aa*\z/)

      expect(values.min).to eq(0)
      expect(values.max).to eq(8)
    end

    it '+ repeats at least once' do
      values = lengths(/\Aa+\z/)

      expect(values.min).to eq(1)
      expect(values.max).to be <= 9
    end

    it '{n} repeats exactly n times' do
      expect(lengths(/\Aa{4}\z/).uniq).to eq([4])
    end

    it '{n,} repeats at least n times and at most 8 more' do
      values = lengths(/\Aa{3,}\z/)

      expect(values.min).to eq(3)
      expect(values.max).to be <= 11
    end

    it '{,m} repeats up to m times' do
      expect(lengths(/\Aa{,3}\z/).uniq.sort).to eq([0, 1, 2, 3])
    end

    it '{n,m} repeats between n and m times' do
      expect(lengths(/\Aa{2,4}\z/).uniq.sort).to eq([2, 3, 4])
    end

    it 'caps a wide finite range at 8 more than its minimum' do
      expect(lengths(/\Aa{2,500}\z/).max).to be <= 10
    end

    it 'treats lazy and possessive variants like the greedy ones' do
      %w[a*? a+? a?? a{2,4}? a*+ a++ a?+].each do |quantified|
        regexp = Regexp.new("\\A#{quantified}\\z")

        expect(regexp).to generate_matching(count: 50)
      end
    end

    it 'repeats a character type, a set and a dot' do
      expect(/\A\d{3}[a-c]{2}.{2}\z/).to generate_matching
    end

    it 'handles a repeated empty node without output or hanging' do
      expect(generate(/\A(?:){3}x\z/)).to eq('x')
      expect(generate(/\A\b+x\z/)).to eq('x')
    end
  end

  describe 'length hints' do
    it 'aims for an exact length through an unbounded quantifier' do
      expect(generate_samples(/\A[a-z]+\z/, count: 50, min_length: 12, max_length: 12).map(&:length).uniq).to eq([12])
    end

    it 'raises the maximum above the default repetition cap when asked for more' do
      expect(generate(/\A[a-z]*\z/, min_length: 30).length).to be >= 30
    end

    it 'respects a maximum' do
      expect(lengths(/\A[a-z]+\z/, max_length: 3).max).to be <= 3
    end

    it 'distributes the length over several quantifiers' do
      samples = generate_samples(/\A[a-z]+-[0-9]+\z/, count: 100, min_length: 9, max_length: 9)

      expect(samples.map(&:length).uniq).to eq([9])
      expect(samples).to all(match(/\A[a-z]+-[0-9]+\z/))
    end

    it 'does not exceed a quantifier maximum to meet a minimum' do
      expect(generate(/\A[a-z]{2,3}\z/, min_length: 10)).to be_nil
    end

    it 'yields no value when the hints cannot be met' do
      expect(generate(/\A[a-z]{8}\z/, max_length: 5)).to be_nil
      expect(generate(/\A[a-z]{3}\z/, min_length: 4)).to be_nil
    end

    it 'lets a minimum raise the output bound' do
      expect(generate(/\Aa{300}\z/, min_length: 300)).to eq('a' * 300)
      expect(generate(/\Aa{300}\z/)).to be_nil
    end

    it 'steers an optional element by the remaining length' do
      samples = generate_samples(/\Aab(?:cd)?\z/, count: 50, max_length: 3)

      expect(samples.uniq).to eq(['ab'])
    end
  end
end
