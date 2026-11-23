# frozen_string_literal: true

require 'regexp_parser'

require_relative 'regex_generation/limits'
require_relative 'regex_generation/codepoints'
require_relative 'regex_generation/universe'
require_relative 'regex_generation/node_kind'
require_relative 'regex_generation/matching'
require_relative 'regex_generation/char_pools'
require_relative 'regex_generation/plan'
require_relative 'regex_generation/tree_cache'
require_relative 'regex_generation/handlers/characters'
require_relative 'regex_generation/handlers/structure'
require_relative 'regex_generation/handlers/assertions'
require_relative 'regex_generation/generator'

module FactoryBakery
  # Generates strings a Regexp matches by walking the regexp_parser syntax
  # tree. It is self-contained on purpose: Ruby stdlib and regexp_parser only,
  # no other part of the gem and no framework (enforced by
  # spec/factory_bakery/regex_generation_isolation_spec.rb). Its only entry
  # point is `RegexGeneration.generate`.
  module RegexGeneration
    class << self
      # Returns a String that `regexp` matches, or nil when none could be
      # produced (an unparseable or unsatisfiable regexp, a bound reached, or
      # no candidate fitting the length hints). It never raises.
      #
      # `min_length` / `max_length` are hints the generator aims for and the
      # result always honours; `random` is anything responding to
      # `rand(Integer)` (the default, `Random`, uses Kernel's global RNG, so
      # `srand` still makes results repeatable).
      def generate(regexp, min_length: nil, max_length: nil, random: Random)
        return nil unless regexp.is_a?(Regexp)

        plan = TreeCache.fetch(regexp)
        low = min_length.to_i
        high = max_length || Float::INFINITY
        Limits::MAX_ATTEMPTS.times do
          candidate = Generator.new(plan, random).call(low, high)
          return candidate if fits?(candidate, low, high, regexp)
        end
        nil
      rescue StandardError
        nil
      end

      private

      # Whether the candidate exists, honours the length bounds and matches.
      def fits?(candidate, low, high, regexp)
        !candidate.nil? && candidate.length.between?(low, high) && regexp.match?(candidate)
      end
    end
  end
end
