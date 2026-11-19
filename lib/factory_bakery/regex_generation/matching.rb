# frozen_string_literal: true

module FactoryBakery
  module RegexGeneration
    # Regexp-level helpers shared by the Plan: a spelling of the regexp that
    # regexp_parser reads the way Onigmo does, and a matcher for a single node.
    module Matching
      # regexp_parser reads the `]` in `[]a]` or `[^]a]` as the end of an empty
      # set, while Onigmo takes it as the first member. Escaping it (outside
      # other escapes) gives the same set an unambiguous spelling.
      LEADING_SET_CLOSER = /(\\.)|(\[\^?)\]/m

      def self.parsable(regexp)
        repaired = regexp.source.gsub(LEADING_SET_CLOSER) { Regexp.last_match(1) || "#{Regexp.last_match(2)}\\]" }
        repaired == regexp.source ? regexp : Regexp.new(repaired, regexp.options)
      end

      # The node alone, anchored, with the flags in force where it sits.
      def self.full_match(node, encoding)
        flags = {
          Regexp::IGNORECASE => node.case_insensitive?,
          Regexp::MULTILINE => node.multiline?,
          Regexp::NOENCODING => encoding == Encoding::BINARY
        }.select { |_flag, on| on }.keys.sum
        Regexp.new("\\A(?:#{node.to_s(:base)})\\z", flags)
      end
    end
  end
end
