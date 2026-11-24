# frozen_string_literal: true

module FactoryBakery
  module RegexGeneration
    module Handlers
      # Nodes that put characters into the candidate: literals, escapes,
      # character sets/types/properties/dot, `\R`, `\X`, and the word
      # boundaries that constrain the character emitted after them.
      module Characters
        LINEBREAKS = ["\n", "\r\n", "\r"].freeze
        WORD_CHAR = /\A\w\z/

        private

        def render_skip(_node, _low, _high); end

        def render_literal(node, _low, _high)
          case_insensitive = node.case_insensitive?
          node.text.each_char { |char| emit_literal(char, case_insensitive) }
        end

        def render_escape(node, _low, _high)
          Codepoints.of(node).each { |codepoint| emit_literal(codepoint.chr(@encoding), false) }
        end

        def render_pool(node, _low, _high)
          emit(pick_char(@plan.pool(node)))
        end

        def render_linebreak(_node, _low, _high)
          emit_free(sample(LINEBREAKS))
        end

        # One grapheme: a single alphanumeric is always a whole cluster.
        def render_grapheme(_node, _low, _high)
          emit_free(sample(Universe::ALNUM))
        end

        # `\b` needs the next character to be a word character exactly when
        # the previous one was not, `\B` the opposite.
        def render_word_boundary(_node, _low, _high)
          @word_next = !word_before?
        end

        def render_nonword_boundary(_node, _low, _high)
          @word_next = word_before?
        end

        def word_before?
          !@out.empty? && word_char?(@out[-1])
        end

        def word_char?(char)
          char.match?(WORD_CHAR)
        end

        # A literal character. A pending lookahead text (see Assertions) is
        # followed while the literals keep agreeing with it.
        def emit_literal(char, case_insensitive)
          head = @prefix[0]
          followed = !head.nil? && (case_insensitive ? char.casecmp?(head) : char == head)
          @prefix = followed ? @prefix[1..] : ''
          emit(followed ? head : cased(char, case_insensitive))
        end

        def cased(char, case_insensitive)
          return char unless case_insensitive

          @random.rand(2).zero? ? char.upcase : char.downcase
        end

        # One character from the node's tiers: a pending lookahead text is
        # followed when the node accepts its next character, and a pending
        # word-boundary constraint narrows the choice.
        def pick_char(tiers)
          candidates = constrained(tiers)
          abort! if candidates.empty?

          head = @prefix[0]
          followed = !head.nil? && candidates.include?(head)
          @prefix = followed ? @prefix[1..] : ''
          followed ? head : sample(candidates)
        end

        def constrained(tiers)
          wanted = @word_next
          @word_next = nil
          preferred = tiers.first || []
          wanted.nil? ? preferred : word_matching(tiers, wanted) || preferred
        end

        def word_matching(tiers, wanted)
          tiers.map { |tier| tier.select { |char| word_char?(char) == wanted } }.find(&:any?)
        end
      end
    end
  end
end
