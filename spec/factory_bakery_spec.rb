# frozen_string_literal: true
require_relative "support/macros/define_constant"

RSpec.describe FactoryBakery::FactoryBakery do
  include DefineConstantMacros

  it "has a version number" do
    expect(FactoryBakery::VERSION).not_to be nil
  end

  let!(:bakery) { described_class.instance }
  let!(:Post) { define_model("Post", title: :string, body: :text) }

  it "should generate the basic fields of a model" do
    post = bakery.bake!(Post)
    expect(post.id).not_to be_nil
  end
end
