# frozen_string_literal: true

require 'spec_helper'

RSpec.describe FactoryBakery::Methods do
  # Mirrors the documented RSpec setup: include the module so examples can
  # call bare bake/bake! (normally via RSpec.configure { |c| c.include ... }).
  include FactoryBakery::Methods

  def target_class
    Class.new { attr_accessor :name, :role }
  end

  it 'provides a bare bake that returns an unsaved object with declared attributes' do
    target = target_class
    FactoryBakery.define(target) { name { 'bare baked' } }

    expect(bake(target).name).to eq('bare baked')
  end

  it 'forwards traits and call-site overrides through bare bake' do
    target = target_class
    FactoryBakery.define(target) do
      name { 'base' }
      trait(:admin) { role { 'admin' } }
    end

    object = bake(target, :admin, name: 'overridden')

    expect(object.name).to eq('overridden')
    expect(object.role).to eq('admin')
  end

  it 'provides a bare bake! that returns the object' do
    target = target_class
    FactoryBakery.define(target) { name { 'bang baked' } }

    expect(bake!(target).name).to eq('bang baked')
  end

  it 'exposes exactly the two delegated methods on the module' do
    expect(described_class.instance_methods(false).sort).to eq(%i[bake bake!])
  end

  it 'does not define bake or bake! on Object or Kernel' do
    expect(Object.instance_methods).not_to include(:bake, :bake!)
    expect(Object.private_instance_methods).not_to include(:bake, :bake!)
    expect(Object.new).not_to respond_to(:bake)
    expect(Object.new).not_to respond_to(:bake!)
    expect(Kernel.private_instance_methods).not_to include(:bake, :bake!)
  end
end
