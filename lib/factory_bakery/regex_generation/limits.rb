# frozen_string_literal: true

module FactoryBakery
  module RegexGeneration
    # Every loop in the generator is bounded by one of these. A candidate that
    # runs into a bound is abandoned (never truncated), so the caller sees "no
    # candidate" instead of junk or an unbounded loop.
    module Limits
      # Nesting of nodes being rendered (the Ruby URI regex nests ~27 deep).
      MAX_DEPTH = 64
      # Nodes visited (every repetition counts) while building one candidate.
      MAX_STEPS = 5_000
      # Characters in one candidate. A larger minimum-length hint raises it.
      MAX_OUTPUT_LENGTH = 256
      # Repetitions beyond a quantifier's minimum when nothing asks for more:
      # `*` yields 0..8, `+` yields 1..9, `{3,}` yields 3..11.
      MAX_REPEAT = 8
      # Nested subexpression calls (`\g<name>`) before a candidate is dropped.
      MAX_CALL_DEPTH = 8
      # Longest filler generated for an absence operator `(?~...)`.
      MAX_ABSENCE_LENGTH = 8
      # Random strings tried before an absence operator gives up.
      ABSENCE_TRIES = 24
      # Candidates built (and verified) per `generate` call.
      MAX_ATTEMPTS = 8
      # Parsed regexes kept in the cache before the oldest is evicted.
      MAX_CACHED_REGEXPS = 256
    end
  end
end
