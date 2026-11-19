# frozen_string_literal: true

require 'spec_helper'
require_relative '../../support/regex_generation_matchers'

RSpec.describe 'RegexGeneration: literals and escapes' do
  include RegexGenerationHelpers

  def generate(regexp, **options)
    FactoryBakery::RegexGeneration.generate(regexp, **options)
  end

  {
    'plain literals' => [/hello world/, 'hello world'],
    'control escapes \t \n \r \f \v \e \a' => [/\t\n\r\f\v\e\a/, "\t\n\r\f\v\e\a"],
    'NUL \0' => [/\0/, "\0"],
    'octal \012' => [/\012/, "\n"],
    'hex \x41' => [/\x41/, 'A'],
    'unicode literal é' => [/é/, 'é'],
    'unicode escape \u00e9' => [/\u00e9/, 'é'],
    'unicode codepoint \u{1F600}' => [/\u{1F600}/, '😀'],
    'unicode codepoint list \u{1F600 41}' => [/\u{1F600 41}/, '😀A'],
    'control \cA' => [/\cA/, "\x01"],
    'control \C-a' => [/\C-a/, "\x01"],
    'escaped metacharacters' => [Regexp.new('\.\*\\\\\/\+\?\(\)\[\]\{\}\|\^\$'), '.*\\/+?()[]{}|^$'],
    'escaped space and hash in free-spacing mode' => [/a\ b\#c/x, 'a b#c']
  }.each do |name, (regexp, expected)|
    it "generates #{name}" do
      expect(generate(regexp)).to eq(expected)
    end
  end

  it 'generates the byte a meta escape \M-a stands for (Ruby only compiles it in a binary regexp)' do
    expect(generate(binary_regexp('\M-a'))).to eq("\xE1".b)
  end

  it 'generates high bytes written as hex escapes in a binary regexp' do
    expect(generate(binary_regexp('\xE1\xFF'))).to eq("\xE1\xFF".b)
  end

  it 'keeps ASCII-only binary regexps in ordinary strings' do
    expect(generate(/\x01/n)).to eq("\x01")
  end

  it 'generates a literal made of several characters, quantifying only the last' do
    values = generate_samples(/ab{2}/, count: 20)

    expect(values.uniq).to eq(['abb'])
  end

  it 'matches the regexp for every construct together' do
    regexp = /\A\t\x41\u00e9\u{1F600}\cA\.\z/

    expect(regexp).to generate_matching(count: 20)
  end
end
