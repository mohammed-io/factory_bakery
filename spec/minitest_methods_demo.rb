# frozen_string_literal: true

# Executable demonstration of opt-in `bake`/`bake!` under Minitest.
# Run with: bundle exec ruby -Ilib spec/minitest_methods_demo.rb

require 'factory_bakery'
require 'minitest/autorun'

class DemoUser
  attr_accessor :name, :role
end

FactoryBakery.define(DemoUser) do
  name { 'bare bake' }
  trait(:admin) { role { 'admin' } }
end

class FactoryBakeryMethodsDemoTest < Minitest::Test
  include FactoryBakery::Methods

  def test_bare_bake_uses_the_factory_definition
    assert_equal 'bare bake', bake(DemoUser).name
  end

  def test_bare_bake_forwards_traits_and_overrides
    user = bake(DemoUser, :admin, name: 'overridden')

    assert_equal 'overridden', user.name
    assert_equal 'admin', user.role
  end

  def test_bare_bake_bang_returns_the_object
    assert_instance_of DemoUser, bake!(DemoUser)
  end

  def test_no_global_bake_methods
    refute Object.new.respond_to?(:bake)
    refute Object.new.respond_to?(:bake!)
  end
end
