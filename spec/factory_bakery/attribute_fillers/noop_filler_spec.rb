# frozen_string_literal: true

require 'spec_helper'

RSpec.describe FactoryBakery::AttributeFillers::NoopFiller do
  include DefineConstantMacros

  describe 'No-op behaviors' do
    context 'when initialized' do
      let!(:Model) do
        define_model('Model', value: :string)
      end

      it 'does not use model_class or attr_name' do
        filler = described_class.new(Model, :value)

        expect(filler).to be_a(described_class)
      end
    end
  end

  describe 'call method' do
    context 'always returns nil' do
      let!(:Model) do
        define_model('Model', value: :string)
      end

      it 'returns nil' do
        filler = described_class.new(Model, :value)

        expect(filler.call).to be_nil
      end

      it 'consistently returns nil across multiple calls' do
        filler = described_class.new(Model, :value)

        10.times do
          expect(filler.call).to be_nil
        end
      end
    end
  end

  describe 'apply_validator method' do
    context 'when called with any validator' do
      let!(:Model) do
        define_model('Model', value: :string)
      end

      it 'returns true (ignores all validators)' do
        filler = described_class.new(Model, :value)
        dummy_validator = double('validator')

        expect(filler.apply_validator(dummy_validator)).to eq(true)
      end
    end
  end

  describe 'Use cases' do
    context 'attributes with database defaults' do
      let!(:User) do
        define_model('User', role: :string) do
          # In a real scenario, role might have a database default
        end
      end

      it 'returns nil allowing database to use default' do
        filler = described_class.new(User, :role)

        expect(filler.call).to be_nil
      end
    end

    context 'virtual attributes (no database column)' do
      let!(:Model) do
        define_model('Model', name: :string)
        # Virtual attribute has no column
      end

      it 'returns nil for virtual attributes' do
        filler = described_class.new(Model, :virtual_attribute)

        expect(filler.call).to be_nil
      end
    end
  end
end
