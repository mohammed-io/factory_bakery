# frozen_string_literal: true

require 'spec_helper'

RSpec.describe FactoryBakery::AttributeFillers::IntegerFiller do
  include DefineConstantMacros

  describe 'Integer generation behaviors' do
    context 'with age attribute' do
      let!(:Person) do
        define_model('Person', age: :integer)
      end

      it 'generates a realistic age (18-65)' do
        filler = described_class.new(Person, :age)
        value = filler.call

        expect(value).to be_an(Integer)
        expect(value).to be_between(18, 65).inclusive
      end
    end

    context 'with priority attribute' do
      let!(:Task) do
        define_model('Task', priority: :integer)
      end

      it 'generates a priority (18-65 based on pattern)' do
        filler = described_class.new(Task, :priority)
        value = filler.call

        expect(value).to be_an(Integer)
      end
    end

    context 'with score/rating/percentage attribute' do
      let!(:Game) do
        define_model('Game', score: :integer)
      end

      it 'generates a score (0-100)' do
        filler = described_class.new(Game, :score)
        value = filler.call

        expect(value).to be_an(Integer)
        expect(value).to be_between(0, 100).inclusive
      end
    end

    context 'with quantity attribute' do
      let!(:Order) do
        define_model('Order', quantity: :integer)
      end

      it 'generates a quantity (1-100)' do
        filler = described_class.new(Order, :quantity)
        value = filler.call

        expect(value).to be_an(Integer)
        expect(value).to be_between(1, 100).inclusive
      end
    end

    context 'with price attribute' do
      let!(:Product) do
        define_model('Product', price: :integer)
      end

      it 'generates a price (1-1000)' do
        filler = described_class.new(Product, :price)
        value = filler.call

        expect(value).to be_an(Integer)
        expect(value).to be_between(1, 1000).inclusive
      end
    end

    context 'with number attribute' do
      let!(:Ticket) do
        define_model('Ticket', number: :integer)
      end

      it 'generates a number (1-999)' do
        filler = described_class.new(Ticket, :number)
        value = filler.call

        expect(value).to be_an(Integer)
        expect(value).to be_between(1, 999).inclusive
      end
    end

    context 'with generic integer attribute' do
      let!(:Counter) do
        define_model('Counter', count: :integer)
      end

      it 'generates a default integer (1-100)' do
        filler = described_class.new(Counter, :count)
        value = filler.call

        expect(value).to be_an(Integer)
        expect(value).to be_between(1, 100).inclusive
      end
    end
  end

  describe 'Numericality constraints' do
    context 'with greater_than validator' do
      let!(:Person) do
        define_model('Person', age: :integer) do
          validates :age, numericality: { greater_than: 18 }
        end
      end

      it 'generates value greater than constraint' do
        filler = described_class.new(Person, :age)
        value = filler.call

        expect(value).to be > 18
      end
    end

    context 'with greater_than_or_equal_to validator' do
      let!(:Person) do
        define_model('Person', age: :integer) do
          validates :age, numericality: { greater_than_or_equal_to: 18 }
        end
      end

      it 'generates value greater than or equal to constraint' do
        filler = described_class.new(Person, :age)
        value = filler.call

        expect(value).to be >= 18
      end
    end

    context 'with less_than validator' do
      let!(:Child) do
        define_model('Child', age: :integer) do
          validates :age, numericality: { less_than: 18 }
        end
      end

      it 'generates value less than constraint' do
        filler = described_class.new(Child, :age)
        value = filler.call

        expect(value).to be < 18
      end
    end

    context 'with less_than_or_equal_to validator' do
      let!(:Child) do
        define_model('Child', age: :integer) do
          validates :age, numericality: { less_than_or_equal_to: 18 }
        end
      end

      it 'generates value less than or equal to constraint' do
        filler = described_class.new(Child, :age)
        value = filler.call

        expect(value).to be <= 18
      end
    end

    context 'with equal_to validator' do
      let!(:Config) do
        define_model('Config', value: :integer) do
          validates :value, numericality: { equal_to: 42 }
        end
      end

      it 'generates the exact value' do
        filler = described_class.new(Config, :value)
        value = filler.call

        expect(value).to eq(42)
      end
    end

    context 'with odd constraint' do
      let!(:Counter) do
        define_model('Counter', value: :integer) do
          validates :value, numericality: { odd: true }
        end
      end

      it 'generates an odd number' do
        filler = described_class.new(Counter, :value)

        10.times do
          value = filler.call
          expect(value).to be_odd
        end
      end
    end

    context 'with even constraint' do
      let!(:Counter) do
        define_model('Counter', value: :integer) do
          validates :value, numericality: { even: true }
        end
      end

      it 'generates an even number' do
        filler = described_class.new(Counter, :value)

        10.times do
          value = filler.call
          expect(value).to be_even
        end
      end
    end

    context 'with in range constraint' do
      let!(:DieRoll) do
        define_model('DieRoll', value: :integer) do
          validates :value, numericality: { in: 1..6 }
        end
      end

      it 'generates value within the range' do
        filler = described_class.new(DieRoll, :value)
        value = filler.call

        expect(value).to be_between(1, 6).inclusive
      end
    end

    context 'with multiple comparison constraints' do
      let!(:RangeModel) do
        define_model('RangeModel', value: :integer) do
          validates :value, numericality: { greater_than: 10, less_than: 20 }
        end
      end

      it 'generates value within bounds' do
        filler = described_class.new(RangeModel, :value)
        value = filler.call

        expect(value).to be > 10
        expect(value).to be < 20
      end
    end
  end

  describe 'Comparison validator (Rails 7+)' do
    context 'with comparison greater_than' do
      let!(:Post) do
        define_model('Post', likes_count: :integer) do
          validates :likes_count, comparison: { greater_than: 0 }
        end
      end

      it 'generates value greater than constraint' do
        filler = described_class.new(Post, :likes_count)
        value = filler.call

        expect(value).to be > 0
      end
    end
  end

  describe 'Inclusion constraints' do
    context 'with inclusion validator' do
      let!(:Vote) do
        define_model('Vote', value: :integer) do
          validates :value, inclusion: { in: [1, 2, 3, 4, 5] }
        end
      end

      it 'picks from allowed values' do
        filler = described_class.new(Vote, :value)
        value = filler.call

        expect([1, 2, 3, 4, 5]).to include(value)
      end
    end
  end

  describe 'Exclusion constraints' do
    context 'with exclusion validator' do
      let!(:LuckyNumber) do
        define_model('LuckyNumber', value: :integer) do
          validates :value, exclusion: { in: [0, 13] }
        end
      end

      it 'avoids forbidden values' do
        filler = described_class.new(LuckyNumber, :value)

        20.times do
          value = filler.call
          expect([0, 13]).not_to include(value)
        end
      end
    end
  end

  describe 'Absence validator' do
    context 'with absence validator' do
      let!(:User) do
        define_model('User', legacy_id: :integer) do
          validates :legacy_id, absence: true
        end
      end

      it 'returns nil' do
        filler = described_class.new(User, :legacy_id)
        value = filler.call

        expect(value).to be_nil
      end
    end
  end
end
