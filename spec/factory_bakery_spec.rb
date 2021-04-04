# frozen_string_literal: true
require_relative "support/macros/define_constant"
require "rubygems"

RAILS_GEM = Gem::Specification.find { |g| g.name == "rails"}.freeze

RSpec.describe FactoryBakery::FactoryBakery do
  include DefineConstantMacros

  it "has a version number" do
    expect(FactoryBakery::VERSION).not_to be nil
  end

  let!(:bakery) { described_class.instance }

  describe "Simple Cases Without Validation" do
    let!(:Dummy) do
      define_model("Dummy",
                   title: :string,
                   body: :text,
                   email: :string,
                   number: :integer,
                   big_number: :big_integer,
                   floating: :float,
                   decimal: :decimal,
                   date: :date,
                   datetime: :datetime,
                   time: :time
      )
    end

    it "should generate the basic fields of a model with valid date types" do
      dummy = bakery.bake!(Dummy)
      expect(dummy.id).not_to be_nil

      expect(dummy.title).to be_a String
      expect(dummy.body).to be_a String
      expect(dummy.email).to be_a String
      expect(dummy.email).to match(/\w+@\w+/)
      expect(dummy.number).to be_a Integer
      expect(dummy.big_number).to be_a Integer
      expect(dummy.floating).to be_a Float
      expect(dummy.decimal).to be_a BigDecimal
      expect(dummy.date).to be_a Date

      if RAILS_GEM.version < Gem::Version.new(6.1)
        expect(dummy.datetime).to be_a Time
        expect(dummy.time).to be_a ActiveRecord::Type::Time::Value
      else
        expect(dummy.datetime).to be_a DateTime
        expect(dummy.time).to be_a DateTime
      end
    end

  end

  let!(:ValidatedDummy) do
    define_model("ValidatedDummy", title: :string, body: :text, email: :string) do
      validates :email, presence: true, length: { maximum: 60 }, uniqueness: { case_sensitive: false }
      validates :body, presence: true, length: { maximum: 30 }
    end
  end
end
