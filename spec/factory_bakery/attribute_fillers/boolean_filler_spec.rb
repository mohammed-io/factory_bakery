# frozen_string_literal: true

require 'spec_helper'

RSpec.describe FactoryBakery::AttributeFillers::BooleanFiller do
  include DefineConstantMacros

  describe 'Boolean generation behaviors' do
    context 'with a generic boolean attribute' do
      let!(:Post) do
        define_model('Post', published: :boolean)
      end

      it 'generates a boolean value' do
        filler = described_class.new(Post, :published)
        value = filler.call

        expect([true, false]).to include(value)
      end

      it 'can generate both true and false over multiple calls' do
        filler = described_class.new(Post, :published)
        values = 20.times.map { filler.call }

        expect(values).to include(true)
        expect(values).to include(false)
      end
    end
  end

  describe 'Acceptance-related attributes' do
    context 'with terms attribute' do
      let!(:Registration) do
        define_model('Registration', terms: :boolean)
      end

      it 'generates accepted value (truthy)' do
        filler = described_class.new(Registration, :terms)
        value = filler.call

        # terms/accepted/agreed patterns return '1'
        expect(value).to eq('1')
      end
    end

    context 'with accepted attribute' do
      let!(:Agreement) do
        define_model('Agreement', accepted: :boolean)
      end

      it 'generates accepted value' do
        filler = described_class.new(Agreement, :accepted)
        value = filler.call

        expect(value).to eq('1')
      end
    end

    context 'with agreed attribute' do
      let!(:Consent) do
        define_model('Consent', agreed: :boolean)
      end

      it 'generates accepted value' do
        filler = described_class.new(Consent, :agreed)
        value = filler.call

        expect(value).to eq('1')
      end
    end
  end

  describe 'Acceptance validator' do
    context 'with acceptance validator' do
      let!(:User) do
        define_model('User', terms_of_service: :boolean) do
          validates :terms_of_service, acceptance: true
        end
      end

      it 'generates the accepted value' do
        filler = described_class.new(User, :terms_of_service)
        value = filler.call

        expect(value).to eq('1')
      end
    end

    context 'with acceptance validator with custom accept value' do
      let!(:Agreement) do
        define_model('Agreement', confirmed: :boolean) do
          validates :confirmed, acceptance: { accept: 'yes' }
        end
      end

      it 'generates the custom accept value' do
        filler = described_class.new(Agreement, :confirmed)
        value = filler.call

        expect(value).to eq('yes')
      end
    end
  end

  describe 'Inclusion constraints' do
    context 'with inclusion validator for boolean values' do
      let!(:Switch) do
        define_model('Switch', state: :boolean) do
          validates :state, inclusion: { in: [true, false] }
        end
      end

      it 'picks from allowed boolean values' do
        filler = described_class.new(Switch, :state)
        value = filler.call

        expect([true, false]).to include(value)
      end
    end

    context 'with inclusion validator for string booleans' do
      let!(:Response) do
        define_model('Response', answer: :string) do
          validates :answer, inclusion: { in: ['true', 'false'] }
        end
      end

      it 'picks from allowed string values' do
        filler = described_class.new(Response, :answer)
        value = filler.call

        expect(['true', 'false']).to include(value)
      end
    end
  end

  describe 'Absence validator' do
    context 'with absence validator' do
      let!(:User) do
        define_model('User', deprecated_flag: :boolean) do
          validates :deprecated_flag, absence: true
        end
      end

      it 'returns nil' do
        filler = described_class.new(User, :deprecated_flag)
        value = filler.call

        expect(value).to be_nil
      end
    end
  end
end
