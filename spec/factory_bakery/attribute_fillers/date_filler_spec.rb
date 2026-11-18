# frozen_string_literal: true

require 'spec_helper'

RSpec.describe FactoryBakery::AttributeFillers::DateFiller do
  include DefineConstantMacros

  describe 'Date generation behaviors' do
    context 'with birthday/dob/born attribute' do
      let!(:Person) do
        define_model('Person', birthday: :date)
      end

      it 'generates a realistic birthday (18-90 years ago)' do
        filler = described_class.new(Person, :birthday)
        value = filler.call
        today = Date.today

        expect(value).to be_a(Date)
        expect((today - value).to_i / 365).to be_between(18, 90).inclusive
      end
    end

    context 'with date_of_birth attribute' do
      let!(:Person) do
        define_model('Person', date_of_birth: :date)
      end

      it 'generates a realistic date of birth' do
        filler = described_class.new(Person, :date_of_birth)
        value = filler.call
        today = Date.today

        expect(value).to be_a(Date)
        expect((today - value).to_i / 365).to be_between(18, 90).inclusive
      end
    end

    context 'with start_date attribute' do
      let!(:Project) do
        define_model('Project', start_date: :date)
      end

      it 'generates a recent past start date (within last year)' do
        filler = described_class.new(Project, :start_date)
        value = filler.call
        today = Date.today

        expect(value).to be_a(Date)
        expect((today - value).to_i).to be_between(0, 365).inclusive
      end
    end

    context 'with end_date attribute' do
      let!(:Project) do
        define_model('Project', end_date: :date)
      end

      it 'generates a future end date (within next year)' do
        filler = described_class.new(Project, :end_date)
        value = filler.call
        today = Date.today

        expect(value).to be_a(Date)
        expect((value - today).to_i).to be_between(0, 365).inclusive
      end
    end

    context 'with expires_at attribute' do
      let!(:Subscription) do
        define_model('Subscription', expires_at: :date)
      end

      it 'generates a future date (within next year)' do
        filler = described_class.new(Subscription, :expires_at)
        value = filler.call
        today = Date.today

        expect(value).to be_a(Date)
        expect((value - today).to_i).to be >= 0
      end
    end

    context 'with due_date attribute' do
      let!(:Task) do
        define_model('Task', due_date: :date)
      end

      it 'generates a future or recent date' do
        filler = described_class.new(Task, :due_date)
        value = filler.call

        expect(value).to be_a(Date)
      end
    end

    context 'with created_at attribute' do
      let!(:Post) do
        define_model('Post', created_at: :date)
      end

      it 'generates a recent past date (within 30 days)' do
        filler = described_class.new(Post, :created_at)
        value = filler.call
        today = Date.today

        expect(value).to be_a(Date)
        expect((today - value).to_i).to be_between(0, 30).inclusive
      end
    end
  end

  describe 'Comparison constraints' do
    context 'with greater_than validator' do
      let!(:Contract) do
        define_model('Contract', start_date: :date) do
          validates :start_date, comparison: { greater_than: Date.today }
        end
      end

      it 'generates date greater than constraint' do
        filler = described_class.new(Contract, :start_date)
        value = filler.call

        expect(value).to be > Date.today
      end
    end

    context 'with greater_than_or_equal_to validator' do
      let!(:Contract) do
        define_model('Contract', start_date: :date) do
          validates :start_date, comparison: { greater_than_or_equal_to: Date.today }
        end
      end

      it 'generates date greater than or equal to constraint' do
        filler = described_class.new(Contract, :start_date)
        value = filler.call

        expect(value).to be >= Date.today
      end
    end

    context 'with less_than validator' do
      let!(:Deadline) do
        define_model('Deadline', cutoff_date: :date) do
          validates :cutoff_date, comparison: { less_than: Date.today >> 3 } # 3 months from now
        end
      end

      it 'generates date less than constraint' do
        three_months_from_now = Date.today >> 3
        filler = described_class.new(Deadline, :cutoff_date)
        value = filler.call

        expect(value).to be < three_months_from_now
      end
    end

    context 'with less_than_or_equal_to validator' do
      let!(:Deadline) do
        define_model('Deadline', cutoff_date: :date) do
          validates :cutoff_date, comparison: { less_than_or_equal_to: Date.today >> 3 }
        end
      end

      it 'generates date less than or equal to constraint' do
        three_months_from_now = Date.today >> 3
        filler = described_class.new(Deadline, :cutoff_date)
        value = filler.call

        expect(value).to be <= three_months_from_now
      end
    end

    context 'with equal_to validator' do
      let!(:Holiday) do
        define_model('Holiday', date: :date) do
          validates :date, comparison: { equal_to: Date.new(2024, 12, 25) }
        end
      end

      it 'generates the exact date' do
        filler = described_class.new(Holiday, :date)
        value = filler.call

        expect(value).to eq(Date.new(2024, 12, 25))
      end
    end

    context 'with multiple comparison constraints' do
      let!(:RangeDate) do
        define_model('RangeDate', value: :date) do
          validates :value, comparison: { greater_than: Date.today - 30, less_than: Date.today + 30 }
        end
      end

      it 'generates date within bounds' do
        filler = described_class.new(RangeDate, :value)
        value = filler.call

        expect(value).to be > (Date.today - 30)
        expect(value).to be < (Date.today + 30)
      end
    end
  end

  describe 'Inclusion constraints' do
    context 'with inclusion validator' do
      let!(:Appointment) do
        define_model('Appointment', date: :date) do
          validates :date, inclusion: { in: [Date.new(2024, 1, 1), Date.new(2024, 7, 4), Date.new(2024, 12, 25)] }
        end
      end

      it 'picks from allowed dates' do
        filler = described_class.new(Appointment, :date)
        value = filler.call

        expect([Date.new(2024, 1, 1), Date.new(2024, 7, 4), Date.new(2024, 12, 25)]).to include(value)
      end
    end
  end

  describe 'Absence validator' do
    context 'with absence validator' do
      let!(:User) do
        define_model('User', deleted_at: :date) do
          validates :deleted_at, absence: true
        end
      end

      it 'returns nil' do
        filler = described_class.new(User, :deleted_at)
        value = filler.call

        expect(value).to be_nil
      end
    end
  end
end
