# frozen_string_literal: true

module FactoryBakery
  module RegexGeneration
    module Handlers
      # Lookaround and the absence operator. Negative lookarounds add nothing
      # (the candidate is verified against the regexp afterwards).
      module Assertions
        FILLER_CHARS = (Universe::ALNUM + Universe::PUNCT).freeze

        private

        # The body is generated aside and becomes the text the characters
        # after it should spell, so `(?=(?i:http|https):)` followed by a URI
        # pattern yields a candidate starting `http:` or `HTTPS:`. Text that
        # is still pending at the end is appended: `foo(?=bar)` gives
        # `foobar`.
        def render_lookahead(node, _low, _high)
          @prefix = generate_aside(node)
        end

        # A positive lookbehind at the very start has nothing before it, so
        # its text is emitted there; elsewhere the preceding output must
        # already satisfy it (checked by the final verification).
        def render_lookbehind(node, _low, _high)
          text = generate_aside(node)
          emit_free(text) if @out.empty?
        end

        # Something that does not contain the body: short printable text,
        # kept only when the compiled `\A(?~body)\z` accepts it.
        def render_absence(node, low, high)
          filler = absence_filler(@plan.matcher(node), absence_length(low, high))
          abort! if filler.nil?

          emit_free(filler)
        end

        def absence_length(low, high)
          shortest = [low, Limits::MAX_ABSENCE_LENGTH].min
          longest = [[high, Limits::MAX_ABSENCE_LENGTH].min, shortest].max
          shortest + @random.rand(longest - shortest + 1)
        end

        def absence_filler(matcher, length)
          Limits::ABSENCE_TRIES.times.lazy.map { random_text(length) }.find { |text| matcher.match?(text) }
        end

        def random_text(length)
          Array.new(length) { sample(FILLER_CHARS) }.join
        end

        # Renders a node's children into a scratch buffer and returns the text.
        def generate_aside(node)
          outer = @out
          @out = String.new(encoding: @encoding)
          @prefix = ''
          render_sequence(node, 0, Float::INFINITY)
          @out.tap { @out = outer }
        end
      end
    end
  end
end
