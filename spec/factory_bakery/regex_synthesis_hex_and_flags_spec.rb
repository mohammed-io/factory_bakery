# frozen_string_literal: true

require 'spec_helper'
require 'active_model'

# Issue #49: declared formats using \h/\H, a character class with an edge '-',
# or the /i option used to exhaust with "could not generate a format-compliant
# value". The regexp_parser-based generator (issue #65) handles them; these
# examples keep the real-world regressions pinned through the public bake API.
RSpec.describe 'regex synthesis: hex escapes, edge hyphens and /i (issue #49)' do
  include DefineConstantMacros

  formats = [
    ['HexFormatColor49', :color, /\A(\h{3}|\h{6})\z/],
    ['HexFragment49', :local_fragment, /\A#[A-Z0-9-]+\Z/i],
    ['ThemeFieldName49', :name, /\A[a-z_][a-z0-9_-]*\z/i],
    ['LocalUsername49', :username, /\A[a-z0-9_]+\z/i],
    ['NonHexChar49', :code, /\A\H\z/]
  ].freeze

  around do |example|
    srand(12_345)
    example.run
  ensure
    srand
  end

  def model_for(name, attribute, regex)
    define_model(name, attribute => :string) do
      validates attribute, format: { with: regex }
    end
  end

  formats.each do |name, attribute, regex|
    it "matches #{regex.inspect} in >= 95% of 200 bakes" do
      model = model_for(name, attribute, regex)

      values = 200.times.map { FactoryBakery.bake(model).public_send(attribute) }

      expect(values).to all(be_a(String))
      expect(values.count { |value| regex.match?(value) }).to be >= 190
    end
  end

  it 'bakes valid records for the hex-color alternation' do
    model = model_for('HexColorBake49', :color, /\A(\h{3}|\h{6})\z/)

    records = 20.times.map { FactoryBakery.bake(model) }

    expect(records).to all(be_valid)
  end
end
