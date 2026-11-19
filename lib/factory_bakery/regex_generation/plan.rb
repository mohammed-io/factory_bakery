# frozen_string_literal: true

module FactoryBakery
  module RegexGeneration
    # A parsed regexp plus everything the generator needs to know about each
    # node, computed once per Regexp (see TreeCache) and read-only afterwards:
    # its kind, how many characters it can produce, the sampling tiers of
    # character nodes and the matcher of absence operators. Building it walks
    # the whole tree, so one Plan can be shared by concurrent generations.
    class Plan
      attr_reader :root, :universe

      def initialize(regexp)
        @universe = Universe.for(regexp.encoding)
        @renderers = {}.compare_by_identity
        @bases = {}.compare_by_identity
        @ranges = {}.compare_by_identity
        @tails = {}.compare_by_identity
        @pools = {}.compare_by_identity
        @matchers = {}.compare_by_identity
        @root = Regexp::Parser.parse(Matching.parsable(regexp))
        measure(@root)
      end

      # The Generator method that renders the node.
      def renderer(node)
        @renderers.fetch(node)
      end

      # [min, max] characters the node produces, quantifier included.
      def range(node)
        @ranges.fetch(node)
      end

      # The same without the node's own quantifier (one repetition).
      def base_range(node)
        @bases.fetch(node)
      end

      # For each child of a sequence-like node: the [min, max] characters its
      # following siblings still need.
      def tails(node)
        @tails.fetch(node)
      end

      def pool(node)
        @pools.fetch(node)
      end

      def matcher(node)
        @matchers.fetch(node)
      end

      private

      def measure(node)
        kind = NodeKind.of(node)
        @renderers[node] = :"render_#{kind}"
        base = @bases[node] = send(:"measure_#{kind}", node)
        @ranges[node] = quantified(base, node.quantifier)
      end

      def measure_skip(_node)
        [0, 0]
      end
      alias measure_word_boundary measure_skip
      alias measure_nonword_boundary measure_skip

      def measure_literal(node)
        [node.text.length] * 2
      end

      def measure_escape(node)
        [Codepoints.of(node).size] * 2
      end

      def measure_pool(node)
        @pools[node] = CharPools.tiers(node, Matching.full_match(node, @universe.encoding), @universe)
        [1, 1]
      end

      def measure_linebreak(_node)
        [1, 2]
      end

      def measure_grapheme(_node)
        [1, 1]
      end

      def measure_sequence(node)
        ranges = node.expressions.map { |child| measure(child) }
        totals = ranges.reverse.reduce([[0, 0]]) do |sums, (min, max)|
          [[sums.first.first + min, sums.first.last + max]] + sums
        end
        @tails[node] = totals.drop(1)
        totals.first
      end
      alias measure_capture measure_sequence

      # Lookaround bodies are generated aside, so they take no room.
      def measure_lookahead(node)
        measure_sequence(node)
        [0, 0]
      end
      alias measure_lookbehind measure_lookahead

      def measure_alternation(node)
        ranges = node.expressions.map { |branch| measure(branch) }
        [ranges.map(&:first).min, ranges.map(&:last).max]
      end

      def measure_conditional(node)
        ranges = node.branches.map { |branch| measure(branch) }
        ranges << [0, 0] if node.branches.one?
        [ranges.map(&:first).min, ranges.map(&:last).max]
      end

      def measure_absence(node)
        @matchers[node] = Matching.full_match(node, @universe.encoding)
        [0, Limits::MAX_ABSENCE_LENGTH]
      end

      def measure_backref(_node)
        [0, Float::INFINITY]
      end
      alias measure_call measure_backref

      def quantified(range, quantifier)
        return range unless quantifier

        upper = quantifier.max.negative? ? Float::INFINITY : quantifier.max
        [product(range.first, quantifier.min), product(range.last, upper)]
      end

      # Zero wins over infinity, so an empty node repeated forever is empty.
      def product(left, right)
        left.zero? || right.zero? ? 0 : left * right
      end
    end
  end
end
