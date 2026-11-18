# frozen_string_literal: true

require 'spec_helper'

RSpec.describe FactoryBakery::AttributeFillers::DateTimeFiller do
  include DefineConstantMacros

  describe 'DateTime generation behaviors' do
    context 'with created_at attribute' do
      let!(:Post) do
        define_model('Post', created_at: :datetime)
      end

      it 'generates a recent past timestamp (within 30 days)' do
        filler = described_class.new(Post, :created_at)
        now = Time.now
        value = filler.call

        expect(value).to be_a(Time)
        expect((now - value).to_i).to be_between(0, 30 * 24 * 3600).inclusive
      end
    end

    context 'with updated_at attribute' do
      let!(:Post) do
        define_model('Post', updated_at: :datetime)
      end

      it 'generates a very recent past timestamp (within 7 days)' do
        filler = described_class.new(Post, :updated_at)
        now = Time.now
        value = filler.call

        expect(value).to be_a(Time)
        expect((now - value).to_i).to be_between(0, 7 * 24 * 3600).inclusive
      end
    end

    context 'with published_at attribute' do
      let!(:Article) do
        define_model('Article', published_at: :datetime)
      end

      it 'generates a past timestamp (within last year)' do
        filler = described_class.new(Article, :published_at)
        now = Time.now
        value = filler.call

        expect(value).to be_a(Time)
        expect((now - value).to_i).to be_between(0, 365 * 24 * 3600).inclusive
      end
    end

    context 'with posted_at attribute' do
      let!(:Comment) do
        define_model('Comment', posted_at: :datetime)
      end

      it 'generates a past timestamp (within last year)' do
        filler = described_class.new(Comment, :posted_at)
        now = Time.now
        value = filler.call

        expect(value).to be_a(Time)
        expect((now - value).to_i).to be_between(0, 365 * 24 * 3600).inclusive
      end
    end

    context 'with starts_at attribute' do
      let!(:Event) do
        define_model('Event', starts_at: :datetime)
      end

      it 'generates a future timestamp (within next 30 days)' do
        filler = described_class.new(Event, :starts_at)
        now = Time.now
        value = filler.call

        expect(value).to be_a(Time)
        expect((value - now).to_i).to be_between(0, 30 * 24 * 3600).inclusive
      end
    end

    context 'with begins_at attribute' do
      let!(:Conference) do
        define_model('Conference', begins_at: :datetime)
      end

      it 'generates a future timestamp (within next 30 days)' do
        filler = described_class.new(Conference, :begins_at)
        now = Time.now
        value = filler.call

        expect(value).to be_a(Time)
        expect((value - now).to_i).to be_between(0, 30 * 24 * 3600).inclusive
      end
    end

    context 'with ends_at attribute' do
      let!(:Event) do
        define_model('Event', ends_at: :datetime)
      end

      it 'generates a future timestamp (31-90 days from now)' do
        filler = described_class.new(Event, :ends_at)
        now = Time.now
        value = filler.call

        expect(value).to be_a(Time)
        expect(value - now).to be_between(31 * 24 * 3600, 90 * 24 * 3600 + 1).inclusive
      end
    end

    context 'with finishes_at attribute' do
      let!(:Project) do
        define_model('Project', finishes_at: :datetime)
      end

      it 'generates a future timestamp (31-90 days from now)' do
        filler = described_class.new(Project, :finishes_at)
        now = Time.now
        value = filler.call

        expect(value).to be_a(Time)
        expect(value - now).to be_between(31 * 24 * 3600, 90 * 24 * 3600 + 1).inclusive
      end
    end

    context 'with expires_at attribute' do
      let!(:Token) do
        define_model('Token', expires_at: :datetime)
      end

      it 'generates a future timestamp (31-90 days from now)' do
        filler = described_class.new(Token, :expires_at)
        now = Time.now
        value = filler.call

        expect(value).to be_a(Time)
        expect(value - now).to be_between(31 * 24 * 3600, 90 * 24 * 3600 + 1).inclusive
      end
    end

    context 'with generic datetime attribute' do
      let!(:Log) do
        define_model('Log', timestamp: :datetime)
      end

      it 'generates current time' do
        filler = described_class.new(Log, :timestamp)
        now = Time.now
        value = filler.call

        expect(value).to be_a(Time)
        expect((now - value).to_i).to be < 5 # Within 5 seconds
      end
    end
  end

  describe 'Comparison constraints' do
    context 'with greater_than validator' do
      let!(:Schedule) do
        define_model('Schedule', start_time: :datetime) do
          validates :start_time, comparison: { greater_than: Time.now }
        end
      end

      it 'generates time greater than constraint' do
        filler = described_class.new(Schedule, :start_time)
        value = filler.call

        expect(value).to be > Time.now - 5 # Allow small time variance
      end
    end

    context 'with greater_than_or_equal_to validator' do
      let!(:Schedule) do
        define_model('Schedule', start_time: :datetime) do
          validates :start_time, comparison: { greater_than_or_equal_to: Time.now }
        end
      end

      it 'generates time greater than or equal to constraint' do
        filler = described_class.new(Schedule, :start_time)
        value = filler.call

        expect(value).to be >= Time.now - 5
      end
    end

    context 'with less_than validator' do
      let!(:Deadline) do
        define_model('Deadline', cutoff: :datetime) do
          validates :cutoff, comparison: { less_than: Time.now + 3600 }
        end
      end

      it 'generates time less than constraint' do
        one_hour_from_now = Time.now + 3600
        filler = described_class.new(Deadline, :cutoff)
        value = filler.call

        expect(value).to be < one_hour_from_now
      end
    end

    context 'with less_than_or_equal_to validator' do
      let!(:Deadline) do
        define_model('Deadline', cutoff: :datetime) do
          validates :cutoff, comparison: { less_than_or_equal_to: Time.now + 3600 }
        end
      end

      it 'generates time less than or equal to constraint' do
        one_hour_from_now = Time.now + 3600
        filler = described_class.new(Deadline, :cutoff)
        value = filler.call

        expect(value).to be <= one_hour_from_now
      end
    end

    context 'with equal_to validator' do
      let!(:FixedEvent) do
        define_model('FixedEvent', time: :datetime) do
          validates :time, comparison: { equal_to: Time.new(2024, 12, 25, 12, 0, 0) }
        end
      end

      it 'generates the exact time' do
        filler = described_class.new(FixedEvent, :time)
        value = filler.call

        expect(value.to_i).to eq(Time.new(2024, 12, 25, 12, 0, 0).to_i)
      end
    end

    context 'with multiple comparison constraints' do
      let!(:RangeTime) do
        define_model('RangeTime', value: :datetime) do
          validates :value, comparison: { greater_than: Time.now - 3600, less_than: Time.now + 3600 }
        end
      end

      it 'generates time within bounds' do
        filler = described_class.new(RangeTime, :value)
        value = filler.call

        expect(value).to be > (Time.now - 3600 - 5)
        expect(value).to be < (Time.now + 3600)
      end
    end
  end

  describe 'Inclusion constraints' do
    context 'with inclusion validator' do
      let!(:ScheduledEvent) do
        t1 = Time.new(2024, 1, 1, 9, 0, 0)
        t2 = Time.new(2024, 1, 1, 12, 0, 0)
        t3 = Time.new(2024, 1, 1, 15, 0, 0)
        define_model('ScheduledEvent', time: :datetime) do
          validates :time, inclusion: { in: [t1, t2, t3] }
        end
      end

      it 'picks from allowed times' do
        filler = described_class.new(ScheduledEvent, :time)
        value = filler.call
        allowed_times = [
          Time.new(2024, 1, 1, 9, 0, 0),
          Time.new(2024, 1, 1, 12, 0, 0),
          Time.new(2024, 1, 1, 15, 0, 0)
        ]

        expect(allowed_times.map(&:to_i)).to include(value.to_i)
      end
    end
  end

  describe 'Absence validator' do
    context 'with absence validator' do
      let!(:User) do
        define_model('User', archived_at: :datetime) do
          validates :archived_at, absence: true
        end
      end

      it 'returns nil' do
        filler = described_class.new(User, :archived_at)
        value = filler.call

        expect(value).to be_nil
      end
    end
  end
end
