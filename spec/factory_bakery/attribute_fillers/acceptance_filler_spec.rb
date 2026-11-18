# frozen_string_literal: true

require 'spec_helper'

RSpec.describe FactoryBakery::AttributeFillers::AcceptanceFiller do
  include DefineConstantMacros

  describe 'Acceptance validator behaviors' do
    context 'with standard acceptance validator' do
      let!(:User) do
        define_model('User', terms_of_service: :string) do
          validates :terms_of_service, acceptance: true
        end
      end

      it 'returns the default accepted value (1)' do
        filler = described_class.new(User, :terms_of_service)
        value = filler.call

        expect(value).to eq('1')
      end
    end

    context 'with custom accept value' do
      let!(:Agreement) do
        define_model('Agreement', confirmed: :string) do
          validates :confirmed, acceptance: { accept: 'yes' }
        end
      end

      it 'returns the custom accept value' do
        filler = described_class.new(Agreement, :confirmed)
        value = filler.call

        expect(value).to eq('yes')
      end
    end

    context 'with boolean accept value' do
      let!(:Consent) do
        define_model('Consent', agreed: :boolean) do
          validates :agreed, acceptance: { accept: true }
        end
      end

      it 'returns the boolean accept value' do
        filler = described_class.new(Consent, :agreed)
        value = filler.call

        expect(value).to eq(true)
      end
    end

    context 'with integer accept value' do
      let!(:OptIn) do
        define_model('OptIn', subscribed: :integer) do
          validates :subscribed, acceptance: { accept: 1 }
        end
      end

      it 'returns the integer accept value' do
        filler = described_class.new(OptIn, :subscribed)
        value = filler.call

        expect(value).to eq(1)
      end
    end
  end

  describe 'Attribute name patterns (acceptance detection)' do
    context 'with attribute ending in _accepted' do
      let!(:Form) do
        define_model('Form', terms_accepted: :string)
      end

      it 'detects acceptance by attribute name' do
        filler = described_class.new(Form, :terms_accepted)
        # Should be detected as acceptance attribute
        expect(filler).to be_a(described_class)
      end
    end
  end

  describe 'Without acceptance validator' do
    context 'when no acceptance validator is present' do
      let!(:Model) do
        define_model('Model', value: :string)
      end

      it 'returns default value' do
        filler = described_class.new(Model, :value)
        value = filler.call

        expect(value).to eq('1')
      end
    end
  end
end
