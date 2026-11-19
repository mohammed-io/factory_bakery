# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    # Private stdlib-only replacements for the framework duration
    # arithmetic the date/datetime generators relied on. Each helper is
    # byte-identical to the framework call it replaces (verified against
    # that framework's 7.2 and 8.1 stacks, across DST and non-DST zones):
    #
    #   * Integer#days / #years on a Date: the framework's Date#advance(days:)
    #     is self + n, and Date#advance(years:) is self >> (12 * n), so plain
    #     Date arithmetic suffices.
    #   * Integer#seconds on a Time-like: Time#since(n) is self + n. A DateTime
    #     counts days, so seconds travel as Rational(n, 86_400).
    #   * Integer#days / #years on a Time: the framework's Time#advance shifts
    #     the calendar part through Date (keeping the wall clock, which is what
    #     makes a 30-day offset stay exactly 30 days across a DST transition)
    #     and rebuilds the time exactly as its Time#change(year:, month:,
    #     day:) does, down to the 10-argument Time.local form that preserves
    #     the original isdst flag.
    module TemporalArithmetic
      class << self
        def date_plus_days(date, days)
          date + days
        end

        def date_plus_years(date, years)
          date >> (12 * years)
        end

        def plus_seconds(time, seconds)
          return time + Rational(seconds, 86_400) if time.is_a?(DateTime)

          time + seconds
        end

        def time_plus_days(time, days)
          rebuild(time, time.to_date.gregorian + days)
        end

        def time_plus_years(time, years)
          rebuild(time, time.to_date.gregorian >> (12 * years))
        end

        private

        # The calendar part moves through Date; the wall clock (hour, minute,
        # second, subsecond) is rebuilt on the new date the same way the
        # framework's Time#change(year:, month:, day:) does.
        def rebuild(time, date)
          if time.utc?
            utc_rebuild(time, date)
          elsif time.zone
            zoned_rebuild(time, date)
          else
            offset_rebuild(time, date)
          end
        end

        def subsecond(time)
          Rational(time.nsec, 1_000_000_000)
        end

        def utc_rebuild(time, date)
          Time.utc(date.year, date.month, date.day, time.hour, time.min, time.sec + subsecond(time))
        end

        # The 10-argument local form preserves the original isdst flag,
        # exactly as the framework's own Time#change does.
        def zoned_rebuild(time, date)
          Time.local(time.sec + subsecond(time), time.min, time.hour,
                     date.day, date.month, date.year, nil, nil, time.isdst, nil)
        end

        def offset_rebuild(time, date)
          Time.new(date.year, date.month, date.day,
                   time.hour, time.min, time.sec + subsecond(time), time.utc_offset)
        end
      end
    end
  end
end
