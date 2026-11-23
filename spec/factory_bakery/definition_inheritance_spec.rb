# frozen_string_literal: true

require 'spec_helper'

# A subclass with no definition of its own bakes with the declarations of its
# nearest ancestor that has one. The record is still the subclass, and an exact
# definition always wins over an inherited one.
RSpec.describe 'definitions inherited by subclasses' do
  let!(:base) { define_class('InheritBase') { attr_accessor :name, :role } }
  let!(:child) { define_class('InheritChild', base) }

  it 'gives a subclass without a definition the declarations of its parent' do
    FactoryBakery.define(base) { name { 'Ada' } }

    record = FactoryBakery.bake(child)

    expect(record).to be_a(child)
    expect(record.name).to eq('Ada')
  end

  it 'does not give a subclass with its own definition the declarations of its parent' do
    FactoryBakery.define(base) do
      name { 'Ada' }
      role { 'admin' }
    end
    FactoryBakery.define(child) { name { 'Grace' } }

    record = FactoryBakery.bake(child)

    expect(record.name).to eq('Grace')
    expect(record.role).to be_nil
  end

  it 'uses the nearest ancestor with a definition for a grandchild' do
    grandchild = define_class('InheritGrandchild', child)
    FactoryBakery.define(base) do
      name { 'Base' }
      role { 'base-role' }
    end
    FactoryBakery.define(child) { name { 'Child' } }

    record = FactoryBakery.bake(grandchild)

    expect(record).to be_a(grandchild)
    expect(record.name).to eq('Child')
    expect(record.role).to be_nil
  end

  it 'leaves a symbol-keyed definition out of a subclass bake' do
    FactoryBakery.define(:inherit_named, klass: base) { name { 'Named' } }

    expect(FactoryBakery.bake(child).name).to be_nil
    expect(FactoryBakery.bake(:inherit_named).name).to eq('Named')
  end

  it 'ignores a definition registered for a module the subclass includes' do
    mixin = stub_const('InheritMixin', Module.new)
    base.include(mixin)
    FactoryBakery.define(mixin) { name { 'From the mixin' } }

    expect(FactoryBakery.bake(child).name).to be_nil
  end
end
