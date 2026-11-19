# frozen_string_literal: true

module FactoryBakery
  module RegexGeneration
    # Builds the sampling tiers of a character-matching node. A tier keeps a
    # candidate only when `matcher` (the node compiled on its own, with the
    # node's own flags) accepts it, so negated sets, intersections, POSIX
    # classes and Unicode properties are exact by construction.
    module CharPools
      # Points sampled inside each range of a set so that a range outside
      # every tier (`[а-я]`) still has candidates.
      RANGE_SAMPLES = 12

      # The non-empty tiers, most natural first.
      def self.tiers(node, matcher, universe)
        near = [Universe::ALNUM, Universe::PUNCT].map { |chars| chars.select { |char| matcher.match?(char) } }
        (near.any?(&:any?) ? near : [wide_matches(node, matcher, universe)]).reject(&:empty?)
      end

      def self.wide_matches(node, matcher, universe)
        member_chars = member_points(node).select { |point| universe.representable?(point) }
                                          .map { |point| universe.char(point) }
        (universe.wide + member_chars).uniq.select { |char| matcher.match?(char) }
      end

      # Codepoints written into a set (literals, escapes, range ends and a few
      # points between them), at any nesting depth.
      def self.member_points(node)
        return range_points(node) if node.type == :set && node.token == :range
        return Codepoints.of(node) if %i[literal escape].include?(node.type)

        node.respond_to?(:expressions) ? node.expressions.flat_map { |child| member_points(child) } : []
      end

      def self.range_points(node)
        low, high = node.expressions.map { |bound| Codepoints.of(bound).first }
        between = (1..RANGE_SAMPLES).map { |index| low + ((high - low) * index / (RANGE_SAMPLES + 1)) }
        [low, high, *between]
      end
    end
  end
end
