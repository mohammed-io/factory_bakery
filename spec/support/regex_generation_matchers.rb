# frozen_string_literal: true

# Helpers for the regex generator specs. Everything is seeded, so a failure
# reproduces exactly.
module RegexGenerationHelpers
  # A binary (/n) regexp built from source text. A literal such as /\xE1/n
  # cannot be written in a spec file without upsetting RuboCop's parser.
  def binary_regexp(source)
    Regexp.new(source, Regexp::NOENCODING)
  end

  def generate_samples(regexp, count: 200, seed: 20_261_119, **options)
    random = Random.new(seed)
    Array.new(count) { FactoryBakery::RegexGeneration.generate(regexp, random: random, **options) }
  end
end

# `expect(regexp).to generate_matching` — every seeded sample must be a String
# the regexp matches. `min_rate:` relaxes that to a share of the samples. The
# failure message names the regex and a bad sample.
RSpec::Matchers.define :generate_matching do |count: 200, min_rate: 1.0, **options|
  include RegexGenerationHelpers

  match do |regexp|
    @samples = generate_samples(regexp, count: count, **options)
    @bad = @samples.reject { |sample| sample && regexp.match?(sample) }
    @rate = 1.0 - (@bad.size.to_f / count)
    @rate >= min_rate
  end

  failure_message do |regexp|
    "#{regexp.inspect}: #{@bad.size}/#{count} generated values did not match " \
      "(match rate #{(@rate * 100).round(1)}%, required #{(min_rate * 100).round(1)}%); " \
      "bad sample: #{@bad.first.inspect}"
  end
end
