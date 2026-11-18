# frozen_string_literal: true

require 'spec_helper'

RSpec.describe FactoryBakery::AttributeFillers::ConfirmationFiller do
  include DefineConstantMacros

  describe 'Confirmation attribute behaviors' do
    context 'with password_confirmation attribute' do
      let!(:User) do
        define_model('User', password: :string, password_confirmation: :string) do
          validates :password, confirmation: true
        end
      end

      it 'matches the source attribute value' do
        filler = described_class.new(User, :password_confirmation)
        filler.set_source_value('secret123')

        expect(filler.call).to eq('secret123')
      end

      it 'returns empty string when no source value is set' do
        filler = described_class.new(User, :password_confirmation)

        expect(filler.call).to eq('')
      end
    end

    context 'with email_confirmation attribute' do
      let!(:Signup) do
        define_model('Signup', email: :string, email_confirmation: :string) do
          validates :email, confirmation: true
        end
      end

      it 'matches the source attribute value' do
        filler = described_class.new(Signup, :email_confirmation)
        filler.set_source_value('user@example.com')

        expect(filler.call).to eq('user@example.com')
      end
    end

    context 'with terms_confirmation attribute' do
      let!(:Agreement) do
        define_model('Agreement', terms: :string, terms_confirmation: :string)
      end

      it 'extracts source attribute name correctly' do
        filler = described_class.new(Agreement, :terms_confirmation)
        expect(filler.instance_variable_get(:@source_attr_name)).to eq('terms')
      end
    end
  end

  describe 'Edge cases' do
    context 'with confirmation attribute having special characters' do
      let!(:User) do
        define_model('User', password: :string, password_confirmation: :string)
      end

      it 'handles special characters in source value' do
        filler = described_class.new(User, :password_confirmation)
        special_value = '!@#$%^&*()_+-=[]{}|;:,.<>?'
        filler.set_source_value(special_value)

        expect(filler.call).to eq(special_value)
      end
    end

    context 'with nil source value' do
      let!(:User) do
        define_model('User', password: :string, password_confirmation: :string)
      end

      it 'handles nil source value' do
        filler = described_class.new(User, :password_confirmation)
        filler.set_source_value(nil)

        expect(filler.call).to eq('')
      end
    end

    context 'with empty string source value' do
      let!(:User) do
        define_model('User', password: :string, password_confirmation: :string)
      end

      it 'handles empty string source value' do
        filler = described_class.new(User, :password_confirmation)
        filler.set_source_value('')

        expect(filler.call).to eq('')
      end
    end

    context 'with very long source value' do
      let!(:User) do
        define_model('User', password: :string, password_confirmation: :string)
      end

      it 'handles long source values' do
        filler = described_class.new(User, :password_confirmation)
        long_value = 'a' * 1000
        filler.set_source_value(long_value)

        expect(filler.call).to eq(long_value)
      end
    end
  end

  describe 'apply_validator method' do
    context 'when called with any validator' do
      let!(:User) do
        define_model('User', password_confirmation: :string)
      end

      it 'returns true (confirmation fillers ignore validators)' do
        filler = described_class.new(User, :password_confirmation)
        dummy_validator = double('validator')

        expect(filler.apply_validator(dummy_validator)).to eq(true)
      end
    end
  end
end
