# frozen_string_literal: true

require 'spec_helper'
require_relative '../../support/regex_generation_matchers'

RSpec.describe 'RegexGeneration: backreferences, conditionals and subexpression calls' do
  include RegexGenerationHelpers

  def generate(regexp, **options)
    FactoryBakery::RegexGeneration.generate(regexp, **options)
  end

  describe 'backreferences' do
    {
      'numbered \1' => /\A(\w{3})-\1\z/,
      'named \k<name>' => /\A(?<word>\w{3})-\k<word>\z/,
      "named \\k'name'" => /\A(?<word>\w{3})-\k'word'\z/,
      'relative \k<-1>' => /\A(\d)(\w)\k<-1>\k<-2>\z/
    }.each do |name, regexp|
      it "repeats the captured text for #{name}" do
        samples = generate_samples(regexp, count: 100)

        expect(regexp).to generate_matching
        expect(samples.uniq.size).to be > 20
      end
    end

    it 'repeats the exact captured text (case-insensitively equal under /i)' do
      samples = generate_samples(/\A(abc)-\1\z/i, count: 100)

      expect(samples).to all(match(/\A(abc)-\1\z/i))
      expect(samples.map { |sample| sample.split('-') }.map(&:uniq).map(&:size).uniq).to eq([1])
    end

    it 'follows a group that sometimes does not capture, retrying the unmatchable paths' do
      expect(/\A(a)?\1\z/).to generate_matching(count: 100)
      expect(generate_samples(/\A(a)?\1\z/, count: 20).uniq).to eq(['aa'])
    end

    it 'yields no value when the referenced group can never have captured' do
      expect(generate(/\A(?:(a)|b)\1\z/)).to eq('aa')
      expect(generate(/\A(?<x>a)|\k<x>\z/)).to eq('a')
    end
  end

  describe 'conditionals' do
    it 'follows the yes branch when the group captured and the no branch when it did not' do
      regexp = /\A(a)?(?(1)b|c)\z/
      samples = generate_samples(regexp, count: 100)

      expect(samples.uniq.sort).to eq(%w[ab c])
    end

    it 'supports a named condition' do
      regexp = /\A(?<open>\()?\d(?(<open>)\))\z/
      samples = generate_samples(regexp, count: 100)

      expect(samples).to all(match(regexp))
      expect(samples.map { |sample| sample.start_with?('(') }.uniq).to contain_exactly(true, false)
    end

    it 'generates nothing for a missing no branch' do
      samples = generate_samples(/\A(a)?x(?(1)y)\z/, count: 100)

      expect(samples.uniq.sort).to eq(%w[axy x])
    end
  end

  describe 'subexpression calls' do
    it 'expands \g<name>' do
      expect(generate_samples(/\A(?<hex>\h{2})-\g<hex>\z/, count: 50)).to all(match(/\A\h\h-\h\h\z/))
    end

    it 'expands \g<1>' do
      expect(generate_samples(/\A(\d{2}):\g<1>\z/, count: 50)).to all(match(/\A\d\d:\d\d\z/))
    end

    it 'expands a relative call \g<-1>' do
      expect(generate_samples(/\A(a)(b)\g<-1>\z/, count: 5).uniq).to eq(['abb'])
    end

    it 'expands the whole pattern with \g<0>' do
      expect(/\A(?:x|\(\g<0>\))\z/.source).to include('g<0>')
      expect(/(?:x|\(\g<0>\))/).to generate_matching(count: 100)
    end

    it 'registers the captures of the called group' do
      expect(/\A(?<d>\d)\g<d>\k<d>\z/).to generate_matching(count: 100)
    end

    it 'terminates recursive patterns by preferring branches that cannot recurse' do
      regexp = /\A(?<tree>x|\(\g<tree>\g<tree>\))\z/

      expect(regexp).to generate_matching(count: 200)
      expect(generate_samples(regexp, count: 200).map(&:length).max).to be > 1
    end

    it 'falls back to every branch when all of them contain calls' do
      regexp = /\A(?<s>x)(?<u>\g<s>|\g<s>y)\g<u>\z/

      expect(regexp).to generate_matching(count: 100)
    end

    it 'abandons a candidate whose calls nest beyond the limit' do
      stub_const('FactoryBakery::RegexGeneration::Limits::MAX_CALL_DEPTH', 0)

      expect(generate(/\A(?<a>x)\g<a>\z/)).to be_nil
    end
  end
end
