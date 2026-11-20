# frozen_string_literal: true

require 'spec_helper'

RSpec.describe FactoryBakery::AttributeFillers::StringFiller do
  include DefineConstantMacros

  describe 'String generation behaviors' do
    context 'with email attribute' do
      let!(:User) do
        define_model('User', email: :string)
      end

      it 'generates a valid email format' do
        filler = described_class.new(User, :email)
        value = filler.call

        expect(value).to match(/\A[^@]+@[^@]+\z/)
      end

      it 'generates unique emails on multiple calls' do
        filler1 = described_class.new(User, :email)
        filler2 = described_class.new(User, :email)

        expect(filler1.call).not_to eq(filler2.call)
      end
    end

    context 'with phone attribute' do
      let!(:User) do
        define_model('User', phone: :string)
      end

      it 'generates a phone number string' do
        filler = described_class.new(User, :phone)
        value = filler.call

        expect(value).to be_a(String)
        expect(value).not_to be_empty
      end
    end

    context 'with name attribute' do
      let!(:User) do
        define_model('User', name: :string)
      end

      it 'generates a person name' do
        filler = described_class.new(User, :name)
        value = filler.call

        expect(value).to be_a(String)
        expect(value).not_to be_empty
        expect(value).to match(/\A[a-zA-Z]+\s+[a-zA-Z]/) # First Last format
      end
    end

    context 'with address attribute' do
      let!(:Location) do
        define_model('Location', address: :string)
      end

      it 'generates a street address' do
        filler = described_class.new(Location, :address)
        value = filler.call

        expect(value).to be_a(String)
        expect(value).not_to be_empty
      end
    end

    context 'with url/website attribute' do
      let!(:Site) do
        define_model('Site', url: :string)
      end

      it 'generates a valid URL' do
        filler = described_class.new(Site, :url)
        value = filler.call

        expect(value).to match(/^https?:\/\//)
      end
    end

    context 'with username attribute' do
      let!(:User) do
        define_model('User', username: :string) do
          validates :username, uniqueness: true
        end
      end

      it 'generates a unique username' do
        filler = described_class.new(User, :username)
        value = filler.call

        expect(value).to be_a(String)
        expect(value).not_to be_empty
      end
    end

    context 'with title attribute' do
      let!(:Article) do
        define_model('Article', title: :string)
      end

      it 'generates a capitalized word' do
        filler = described_class.new(Article, :title)
        value = filler.call

        expect(value).to be_a(String)
        expect(value).not_to be_empty
      end
    end

    context 'with body attribute' do
      let!(:Article) do
        define_model('Article', body: :text)
      end

      it 'generates a sentence' do
        filler = described_class.new(Article, :body)
        value = filler.call

        expect(value).to be_a(String)
        expect(value).to match(/\w+ \w+/) # Multiple words
      end
    end

    context 'with code attribute' do
      let!(:Product) do
        define_model('Product', code: :string)
      end

      it 'generates a code string' do
        filler = described_class.new(Product, :code)
        value = filler.call

        expect(value).to be_a(String)
        expect(value).not_to be_empty
      end
    end

    context 'with password attribute' do
      let!(:User) do
        define_model('User', password: :string)
      end

      it 'generates a password string' do
        filler = described_class.new(User, :password)
        value = filler.call

        expect(value).to be_a(String)
        expect(value).not_to be_empty
      end
    end

    context 'with priority attribute' do
      let!(:Task) do
        define_model('Task', priority: :string)
      end

      it 'generates a priority as string number' do
        filler = described_class.new(Task, :priority)
        value = filler.call

        expect(value).to match(/\A[1-5]\z/)
      end
    end
  end

  describe 'Length constraints' do
    context 'with maximum length validator' do
      let!(:PostMax) do
        define_model('PostMax', title: :string) do
          validates :title, length: { maximum: 10 }
        end
      end

      it 'respects the maximum length' do
        filler = described_class.new(PostMax, :title)
        value = filler.call

        expect(value.length).to be <= 10
      end
    end

    context 'with minimum length validator' do
      let!(:PostMin) do
        define_model('PostMin', title: :string) do
          validates :title, length: { minimum: 20 }
        end
      end

      it 'respects the minimum length' do
        DEBUG = true
        filler = described_class.new(PostMin, :title)
        value = filler.call

        expect(value.length).to be >= 20
      end
    end

    context 'with exact length validator' do
      let!(:PostExact) do
        define_model('PostExact', code: :string) do
          validates :code, length: { is: 5 }
        end
      end

      it 'generates exact length' do
        filler = described_class.new(PostExact, :code)
        value = filler.call

        expect(value.length).to eq(5)
      end
    end

    context 'with range length validator' do
      let!(:PostRange) do
        define_model('PostRange', title: :string) do
          validates :title, length: { in: 5..10 }
        end
      end

      it 'generates within the range' do
        filler = described_class.new(PostRange, :title)
        value = filler.call

        expect(value.length).to be_between(5, 10).inclusive
      end
    end

    context 'with database column limit' do
      let!(:PostDb) do
        define_model('PostDb', short_field: { type: :string, limit: 8 })
      end

      it 'respects database limit' do
        filler = described_class.new(PostDb, :short_field)
        value = filler.call

        expect(value.length).to be <= 8
      end
    end
  end

  describe 'Format constraints' do
    context 'with format validator' do
      let!(:Product) do
        define_model('Product', sku: :string) do
          validates :sku, format: { with: /\A[A-Z]{3}-\d{4}\z/ }
        end
      end

      it 'generates value matching the format' do
        filler = described_class.new(Product, :sku)
        value = filler.call

        expect(value).to match(/\A[A-Z]{3}-\d{4}\z/)
      end
    end
  end

  describe 'Inclusion constraints' do
    context 'with inclusion validator' do
      let!(:Task) do
        define_model('Task', status: :string) do
          validates :status, inclusion: { in: %w[pending in_progress completed] }
        end
      end

      it 'picks from allowed values' do
        filler = described_class.new(Task, :status)
        value = filler.call

        expect(%w[pending in_progress completed]).to include(value)
      end
    end
  end

  describe 'Exclusion constraints' do
    context 'with exclusion validator' do
      let!(:User) do
        define_model('User', username: :string) do
          validates :username, exclusion: { in: %w[admin root superuser] }
        end
      end

      it 'avoids forbidden values' do
        filler = described_class.new(User, :username)

        10.times do
          value = filler.call
          expect(%w[admin root superuser]).not_to include(value)
        end
      end
    end
  end

  describe 'Absence validator' do
    context 'with absence validator' do
      let!(:User) do
        define_model('User', middle_name: :string) do
          validates :middle_name, absence: true
        end
      end

      it 'returns nil' do
        filler = described_class.new(User, :middle_name)
        value = filler.call

        expect(value).to be_nil
      end
    end
  end

  describe 'Generic string without special patterns' do
    let!(:GenericPost) do
      define_model('GenericPost', description: :string)
    end

    it 'generates a word' do
      filler = described_class.new(GenericPost, :description)
      value = filler.call

      expect(value).to be_a(String)
      expect(value).not_to be_empty
    end
  end

  describe 'a required attribute whose format admits whitespace' do
    let!(:Ad) do
      define_model('Ad', name: :string) do
        validates :name, presence: true, format: { with: /\A[a\s]*\z/ }
      end
    end

    it 'never generates a blank value' do
      values = Array.new(60) { described_class.new(Ad, :name).call }

      expect(values).to all(match(/[^[:space:]]/))
    end
  end
end
