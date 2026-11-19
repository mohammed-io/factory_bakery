# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'STI discriminator column' do
  include DefineConstantMacros

  describe 'the default `type` inheritance column' do
    let!(:vehicle_model) do
      define_model('Vehicle', type: :string, name: :string)
    end

    before do
      define_class('Car', vehicle_model)
    end

    it 'preserves the subclass name Rails assigns in new, while filling other columns' do
      record = FactoryBakery.bake(Car, fill_optional: true)

      expect(record.type).to eq(Car.sti_name)
      expect(record.name).to be_a(String)
      expect(record.name).not_to be_empty
    end

    it 'persists a discriminator that reloads as the subclass without SubclassNotFound' do
      record = FactoryBakery.bake!(Car)

      expect(Vehicle.find(record.id)).to be_a(Car)
    end

    it 'leaves the base-class discriminator as Rails initialized it' do
      expect(FactoryBakery.bake(Vehicle).type).to eq(Vehicle.new.type)
    end

    it 'still honours a call-site override of the discriminator' do
      record = FactoryBakery.bake(Car, type: 'ExplicitType')

      expect(record.type).to eq('ExplicitType')
    end

    it 'still honours a factory declaration of the discriminator' do
      FactoryBakery.define(Car) do
        type { 'DeclaredType' }
      end

      expect(FactoryBakery.bake(Car).type).to eq('DeclaredType')
    end

    it 'still honours a trait declaration of the discriminator' do
      FactoryBakery.define(Car) do
        trait :special do
          type { 'TraitType' }
        end
      end

      expect(FactoryBakery.bake(Car, :special).type).to eq('TraitType')
    end
  end

  describe 'a custom inheritance column' do
    let!(:machine_model) do
      define_model('Machine', kind: :string, label: :string) do
        self.inheritance_column = 'kind'
      end
    end

    before do
      define_class('Robot', machine_model)
    end

    it 'preserves the subclass name in the custom column' do
      record = FactoryBakery.bake(Robot, fill_optional: true)

      expect(record.kind).to eq(Robot.sti_name)
      expect(record.label).to be_a(String)
    end

    it 'persists a custom discriminator that reloads as the subclass' do
      record = FactoryBakery.bake!(Robot)

      expect(Machine.find(record.id)).to be_a(Robot)
    end

    it 'leaves the base-class custom discriminator as Rails initialized it' do
      expect(FactoryBakery.bake(Machine).kind).to eq(Machine.new.kind)
    end
  end

  describe 'a plain `type` column when STI is disabled' do
    let!(:label_model) do
      define_model('Label', type: :string) do
        self.inheritance_column = nil
      end
    end

    it 'still fills the column heuristically' do
      record = FactoryBakery.bake(label_model, fill_optional: true)

      expect(record.type).to be_a(String)
      expect(record.type).not_to be_empty
    end

    it 'still honours a call-site override of the column' do
      record = FactoryBakery.bake(label_model, type: 'known')

      expect(record.type).to eq('known')
    end
  end
end
