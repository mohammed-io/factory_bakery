# frozen_string_literal: true

require 'spec_helper'
require_relative '../../support/regex_generation_matchers'

RSpec.describe 'RegexGeneration: character types' do
  include RegexGenerationHelpers

  def sample_text(regexp, **options)
    generate_samples(regexp, count: 500, **options).join
  end

  {
    '\d' => [/\A\d+\z/, /\D/],
    '\D' => [/\A\D+\z/, /\d/],
    '\w' => [/\A\w+\z/, /\W/],
    '\W' => [/\A\W+\z/, /\w/],
    '\s' => [/\A\s+\z/, /\S/],
    '\S' => [/\A\S+\z/, /\s/],
    '\h' => [/\A\h+\z/, /\H/],
    '\H' => [/\A\H+\z/, /\h/]
  }.each do |name, (regexp, forbidden)|
    it "generates only characters #{name} accepts" do
      expect(regexp).to generate_matching(count: 500)
      expect(sample_text(regexp)).not_to match(forbidden)
    end
  end

  describe 'dot' do
    it 'never produces a newline without the m flag' do
      expect(sample_text(/\A.{1,10}\z/)).not_to include("\n")
    end

    it 'generates values for a regexp with the m flag (where dot may match a newline)' do
      expect(/\A.{1,10}\z/m).to generate_matching(count: 100)
    end
  end

  describe '\R (linebreak)' do
    it 'generates a linebreak sequence' do
      samples = generate_samples(/\A\R\z/, count: 100)

      expect(samples).to all(match(/\A(?:\n|\r\n|\r)\z/))
      expect(samples.uniq.size).to be > 1
    end
  end

  describe '\X (extended grapheme)' do
    it 'generates exactly one grapheme' do
      samples = generate_samples(/\A\X\z/, count: 100)

      expect(samples.map { |sample| sample.grapheme_clusters.size }).to all(eq(1))
    end
  end
end
