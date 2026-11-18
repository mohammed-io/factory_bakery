# frozen_string_literal: true

require 'spec_helper'

RSpec.describe FactoryBakery::AttributeFillers::EnumFiller do
  include DefineConstantMacros

  describe 'Enum generation behaviors' do
    context 'with Rails 5+ enum (defined_enums)' do
      let!(:User) do
        model = define_model('User', status: :integer)
        # Manually set defined_enums since Class.new + enum doesn't work in Rails 8
        model.defined_enums = { 'status' => { 'active' => 0, 'inactive' => 1, 'pending' => 2 } }
        model
      end

      it 'picks from the enum string values' do
        filler = described_class.new(User, :status)
        value = filler.call

        expect(%w[active inactive pending]).to include(value)
      end

      it 'can generate any of the enum values over multiple calls' do
        filler = described_class.new(User, :status)
        values = 30.times.map { filler.call }

        expect(values.uniq).to include('active', 'inactive', 'pending')
      end
    end

    context 'with singular enum name' do
      let!(:Order) do
        model = define_model('Order', state: :integer)
        model.defined_enums = { 'state' => { 'cart' => 0, 'checkout' => 1, 'purchased' => 2, 'shipped' => 3 } }
        model
      end

      it 'picks from the enum values' do
        filler = described_class.new(Order, :state)
        value = filler.call

        expect(%w[cart checkout purchased shipped]).to include(value)
      end
    end
  end

  describe 'Inclusion validator as enum fallback' do
    context 'with inclusion validator containing string values' do
      let!(:Priority) do
        define_model('Priority', level: :string) do
          validates :level, inclusion: { in: %w[low medium high urgent] }
        end
      end

      it 'detects and treats as enum' do
        filler = described_class.new(Priority, :level)
        value = filler.call

        expect(%w[low medium high urgent]).to include(value)
      end
    end
  end

  describe 'Empty enum values' do
    context 'when no enum definition is found' do
      let!(:Model) do
        define_model('Model', value: :string)
      end

      it 'returns nil' do
        filler = described_class.new(Model, :value)
        value = filler.call

        expect(value).to be_nil
      end
    end
  end

  describe 'Absence validator' do
    context 'with absence validator on enum' do
      let!(:User) do
        model = define_model('User', role: :integer)
        model.defined_enums = { 'role' => { 'admin' => 0, 'user' => 1, 'guest' => 2 } }
        model.class_eval { validates :role, absence: true }
        model
      end

      it 'returns nil' do
        filler = described_class.new(User, :role)
        value = filler.call

        expect(value).to be_nil
      end
    end
  end

  describe 'Explicit inclusion override' do
    context 'when both enum and explicit inclusion validator exist' do
      let!(:Product) do
        model = define_model('Product', category: :integer)
        model.defined_enums = { 'category' => { 'electronics' => 0, 'clothing' => 1, 'food' => 2 } }
        model
      end

      it 'picks from enum values by default' do
        filler = described_class.new(Product, :category)
        value = filler.call

        expect(%w[electronics clothing food]).to include(value)
      end
    end
  end
end
