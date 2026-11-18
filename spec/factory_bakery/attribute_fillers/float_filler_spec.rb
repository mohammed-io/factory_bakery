# frozen_string_literal: true

require 'spec_helper'

RSpec.describe FactoryBakery::AttributeFillers::FloatFiller do
  include DefineConstantMacros

  describe 'Float generation behaviors' do
    context 'with rating attribute' do
      let!(:Review) do
        define_model('Review', rating: :float)
      end

      it 'generates a rating (0.0-5.0)' do
        filler = described_class.new(Review, :rating)
        value = filler.call

        expect(value).to be_a(Float)
        expect(value).to be_between(0.0, 5.0).inclusive
      end
    end

    context 'with percentage attribute' do
      let!(:Metric) do
        define_model('Metric', percentage: :float)
      end

      it 'generates a percentage (0.0-100.0)' do
        filler = described_class.new(Metric, :percentage)
        value = filler.call

        expect(value).to be_a(Float)
        expect(value).to be_between(0.0, 100.0).inclusive
      end
    end

    context 'with price attribute' do
      let!(:Product) do
        define_model('Product', price: :float)
      end

      it 'generates a price (1.0-1000.0)' do
        filler = described_class.new(Product, :price)
        value = filler.call

        expect(value).to be_a(Float)
        expect(value).to be_between(1.0, 1000.0).inclusive
      end
    end

    context 'with generic float attribute' do
      let!(:Measurement) do
        define_model('Measurement', value: :float)
      end

      it 'generates a default float (0.0-100.0)' do
        filler = described_class.new(Measurement, :value)
        value = filler.call

        expect(value).to be_a(Float)
        expect(value).to be_between(0.0, 100.0).inclusive
      end
    end
  end

  describe 'Numericality constraints' do
    context 'with greater_than validator' do
      let!(:Product) do
        define_model('Product', price: :float) do
          validates :price, numericality: { greater_than: 0 }
        end
      end

      it 'generates value greater than constraint' do
        filler = described_class.new(Product, :price)
        value = filler.call

        expect(value).to be > 0.0
      end
    end

    context 'with greater_than_or_equal_to validator' do
      let!(:Product) do
        define_model('Product', price: :float) do
          validates :price, numericality: { greater_than_or_equal_to: 0 }
        end
      end

      it 'generates value greater than or equal to constraint' do
        filler = described_class.new(Product, :price)
        value = filler.call

        expect(value).to be >= 0.0
      end
    end

    context 'with less_than validator' do
      let!(:Discount) do
        define_model('Discount', rate: :float) do
          validates :rate, numericality: { less_than: 1.0 }
        end
      end

      it 'generates value less than constraint' do
        filler = described_class.new(Discount, :rate)
        value = filler.call

        expect(value).to be < 1.0
      end
    end

    context 'with less_than_or_equal_to validator' do
      let!(:Discount) do
        define_model('Discount', rate: :float) do
          validates :rate, numericality: { less_than_or_equal_to: 1.0 }
        end
      end

      it 'generates value less than or equal to constraint' do
        filler = described_class.new(Discount, :rate)
        value = filler.call

        expect(value).to be <= 1.0
      end
    end

    context 'with equal_to validator' do
      let!(:Constant) do
        define_model('Constant', value: :float) do
          validates :value, numericality: { equal_to: 3.14 }
        end
      end

      it 'generates the exact value' do
        filler = described_class.new(Constant, :value)
        value = filler.call

        expect(value).to eq(3.14)
      end
    end

    context 'with in range constraint' do
      let!(:Probability) do
        define_model('Probability', value: :float) do
          validates :value, numericality: { in: 0.0..1.0 }
        end
      end

      it 'generates value within the range' do
        filler = described_class.new(Probability, :value)
        value = filler.call

        expect(value).to be_between(0.0, 1.0).inclusive
      end
    end

    context 'with multiple comparison constraints' do
      let!(:Temperature) do
        define_model('Temperature', celsius: :float) do
          validates :celsius, numericality: { greater_than: -10, less_than: 40 }
        end
      end

      it 'generates value within bounds' do
        filler = described_class.new(Temperature, :celsius)
        value = filler.call

        expect(value).to be > -10.0
        expect(value).to be < 40.0
      end
    end
  end

  describe 'Precision and scale' do
    context 'with decimal column having scale' do
      let!(:Price) do
        define_model('Price') do
          # Table will be created with proper decimal column in before block
        end
      end

      before do
        # Drop table if exists, then create with decimal column having scale
        ActiveRecord::Base.connection.drop_table(:prices, if_exists: true)
        ActiveRecord::Base.connection.create_table(:prices) do |t|
          t.decimal :amount, precision: 10, scale: 2
        end
        Price.reset_column_information
      end

      it 'respects the scale (decimal places)' do
        filler = described_class.new(Price, :amount)
        value = filler.call

        expect(value).to be_a(Numeric)
        # Check that value has at most 2 decimal places
        decimal_places = (value.to_s.split('.').last || '').length
        expect(decimal_places).to be <= 2
      end
    end
  end

  describe 'Inclusion constraints' do
    context 'with inclusion validator' do
      let!(:TaxRate) do
        define_model('TaxRate', value: :float) do
          validates :value, inclusion: { in: [0.05, 0.10, 0.15, 0.20] }
        end
      end

      it 'picks from allowed values' do
        filler = described_class.new(TaxRate, :value)
        value = filler.call

        expect([0.05, 0.10, 0.15, 0.20]).to include(value)
      end
    end
  end

  describe 'Exclusion constraints' do
    context 'with exclusion validator' do
      let!(:SpecialValue) do
        define_model('SpecialValue', amount: :float) do
          validates :amount, exclusion: { in: [0.0, 1.0] }
        end
      end

      it 'avoids forbidden values' do
        filler = described_class.new(SpecialValue, :amount)

        20.times do
          value = filler.call
          expect([0.0, 1.0]).not_to include(value)
        end
      end
    end
  end

  describe 'Absence validator' do
    context 'with absence validator' do
      let!(:User) do
        define_model('User', deprecated_score: :float) do
          validates :deprecated_score, absence: true
        end
      end

      it 'returns nil' do
        filler = described_class.new(User, :deprecated_score)
        value = filler.call

        expect(value).to be_nil
      end
    end
  end
end
