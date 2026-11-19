# frozen_string_literal: true

module FactoryBakery
  module RegexGeneration
    # Plans per Regexp, so each regex is parsed and analysed once. Bounded
    # (the oldest entry is evicted first) and guarded by a mutex; a Plan is
    # read-only once built, so generations share it freely.
    module TreeCache
      LOCK = Mutex.new
      @entries = {}

      def self.fetch(regexp)
        LOCK.synchronize do
          @entries.fetch(regexp) do
            @entries.shift if @entries.size >= Limits::MAX_CACHED_REGEXPS
            @entries[regexp] = Plan.new(regexp)
          end
        end
      end
    end
  end
end
