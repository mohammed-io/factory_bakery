# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    # A pure, bounded string synthesizer for the practical subset of Ruby
    # regex syntax that FFaker's from_regexp cannot express: groups,
    # alternation, inline flags and POSIX character classes.
    #
    # It reads only the Regexp's source string (no framework reflection) and
    # does strictly bounded work: parsing is capped by node count and nesting
    # depth, generation by repetition count, recursion depth and output length.
    # Any construct outside the supported subset raises Unsupported, which the
    # caller turns into "no candidate" and therefore its V5 exhaustion error —
    # never literal junk and never an unbounded loop.
    class RegexSynthesizer
      class Unsupported < StandardError; end

      MAX_DEPTH = 20
      MAX_NODES = 500
      MAX_REPEAT = 12
      MAX_OUTPUT_LENGTH = 256

      BASE_CHARS = ((32..126).map(&:chr) + ["\t", "\n", "\r", "\f", "\v"]).freeze
      DOT_CHARS = (BASE_CHARS - ["\n"]).freeze
      DIGITS = ('0'..'9').to_a.freeze
      LOWER = ('a'..'z').to_a.freeze
      UPPER = ('A'..'Z').to_a.freeze
      WORD = (LOWER + UPPER + DIGITS + ['_']).freeze
      SPACES = [' ', "\t", "\n", "\r", "\f", "\v"].freeze

      POSIX_CLASSES = {
        'alpha' => LOWER + UPPER,
        'digit' => DIGITS,
        'alnum' => LOWER + UPPER + DIGITS,
        'lower' => LOWER,
        'upper' => UPPER,
        'space' => SPACES,
        'blank' => [' ', "\t"],
        'xdigit' => DIGITS + ('a'..'f').to_a + ('A'..'F').to_a,
        'word' => WORD,
        'punct' => BASE_CHARS.select { |c| /[[:punct:]]/.match?(c) },
        'graph' => BASE_CHARS.reject { |c| c.match?(/\s/) },
        'print' => BASE_CHARS,
        'cntrl' => ["\t", "\n", "\r", "\f", "\v"]
      }.freeze

      def self.negate(chars)
        BASE_CHARS - chars
      end

      def initialize(regex)
        @source = regex.respond_to?(:source) ? regex.source : regex.to_s
      end

      # Regexes using only syntax FFaker handles faithfully stay on the FFaker
      # path. This preserves V5 regeneration semantics for the simple,
      # probe-6-style shapes and keeps their behavior unchanged. Escapes and
      # character-class contents are stripped before the structural check so
      # an escaped "\\(" is not mistaken for a group.
      def ffaker_expressible?
        return false if @source.include?('[[') # POSIX class
        return false if @source.match?(/\\[pPk1-9]/) # property / backreference

        stripped = @source.gsub(/\\./m, '').gsub(/\[(?:\\.|[^\]])*\]/m, '')
        !stripped.match?(/[|()]/)
      end

      def supported?
        !ast.nil?
      end

      # Returns a single bounded, generated candidate, or nil when the regex
      # is outside the supported subset (or generation exceeded its budget).
      def generate
        node = ast
        return nil unless node

        output = +''
        render(node, output, 0)
        output
      rescue StandardError
        nil
      end

      private

      def ast
        return @ast if defined?(@ast)

        @ast = Parser.new(@source).parse
      rescue Unsupported
        @ast = nil
      end

      def render(node, output, depth)
        raise Unsupported, 'render depth' if depth > MAX_DEPTH

        case node[0]
        when :empty
          nil
        when :literal
          output << node[1]
        when :class
          chars = node[1]
          raise Unsupported, 'empty class' if chars.empty?

          output << chars.sample
        when :seq
          node[1].each { |child| render(child, output, depth + 1) }
        when :alt
          render(node[1].sample, output, depth + 1)
        when :group
          render(node[1], output, depth + 1)
        when :repeat
          render_repeat(node, output, depth)
        else
          raise Unsupported, "unknown node #{node[0]}"
        end

        raise Unsupported, 'output length' if output.length > MAX_OUTPUT_LENGTH
      end

      def render_repeat(node, output, depth)
        min = node[2]
        max = node[3]
        upper = max.nil? ? min + MAX_REPEAT : [max, min + MAX_REPEAT].min
        count = rand(min..upper)
        count.times { render(node[1], output, depth + 1) }
      end

      # Recursive-descent parser over the Regexp source for the supported
      # subset. Every node creation is budgeted; unsupported syntax raises.
      class Parser
        ZERO_WIDTH = %w[A z Z b B G].freeze
        CLASS_ESCAPES = {
          'd' => DIGITS, 'D' => RegexSynthesizer.negate(DIGITS),
          'w' => WORD, 'W' => RegexSynthesizer.negate(WORD),
          's' => SPACES, 'S' => RegexSynthesizer.negate(SPACES),
          'n' => ["\n"], 't' => ["\t"], 'r' => ["\r"],
          'f' => ["\f"], 'v' => ["\v"]
        }.freeze

        def initialize(source)
          @chars = source.chars
          @index = 0
          @nodes = 0
          @depth = 0
        end

        def parse
          node = parse_alternation
          raise Unsupported, 'trailing input' unless @index >= @chars.length

          node
        end

        private

        def peek
          @chars[@index]
        end

        def advance
          char = @chars[@index]
          @index += 1
          char
        end

        def node(kind, *args)
          @nodes += 1
          raise Unsupported, 'node budget' if @nodes > MAX_NODES

          [kind, *args]
        end

        def parse_alternation
          branches = [parse_sequence]
          while peek == '|'
            advance
            branches << parse_sequence
          end
          branches.length == 1 ? branches.first : node(:alt, branches)
        end

        def parse_sequence
          items = []
          items << parse_term while @index < @chars.length && !['|', ')'].include?(peek)
          node(:seq, items)
        end

        def parse_term
          atom = parse_atom
          quantifier = parse_quantifier
          return atom unless quantifier

          node(:repeat, atom, quantifier[0], quantifier[1])
        end

        def parse_quantifier
          case peek
          when '*'
            advance
            consume_lazy
            [0, nil]
          when '+'
            advance
            consume_lazy
            [1, nil]
          when '?'
            advance
            consume_lazy
            [0, 1]
          when '{'
            parse_brace_quantifier
          end
        end

        def parse_brace_quantifier
          marker = @index
          advance # '{'
          lower = +''
          lower << advance while peek&.match?(/\d/)

          if peek == ','
            advance
            upper = +''
            upper << advance while peek&.match?(/\d/)
            return finish_brace(marker, lower.empty? ? 0 : lower.to_i,
                                upper.empty? ? nil : upper.to_i)
          end

          return finish_brace(marker, lower.to_i, lower.to_i) if peek == '}' && !lower.empty?

          @index = marker
          nil
        end

        def finish_brace(marker, lower, upper)
          raise Unsupported, 'inverted quantifier' if upper && upper < lower

          advance # '}'
          consume_lazy
          [lower, upper]
        rescue Unsupported
          @index = marker
          raise
        end

        def consume_lazy
          advance if peek == '?'
        end

        def parse_atom
          raise Unsupported, 'depth' if @depth > MAX_DEPTH

          char = advance
          case char
          when '(' then parse_group
          when '[' then parse_class
          when '\\' then parse_escape
          when '^', '$' then node(:empty)
          when '.' then char_node(DOT_CHARS)
          when '|', ')', '*', '+', '?', '{', '}' then raise Unsupported, "bare #{char}"
          else node(:literal, char)
          end
        end

        def parse_group
          @depth += 1
          consume_group_prefix if peek == '?'
          inner = parse_alternation
          raise Unsupported, 'unclosed group' unless peek == ')'

          advance
          node(:group, inner)
        ensure
          @depth -= 1
        end

        # Consumes a leading '?' already seen by parse_group. Lookarounds and
        # conditionals raise Unsupported because they cannot be synthesized.
        def consume_group_prefix
          advance # '?'
          case peek
          when ':'
            advance # non-capturing
            true
          when '=', '!', '<', '('
            raise Unsupported, 'lookaround/conditional'
          else
            # Flag directive: (?i), (?i:...), (?mix:...), (?-mix:...). The
            # flags themselves are zero-width for synthesis; the actual
            # Regexp still verifies case sensitivity on the generated value.
            advance while @index < @chars.length && !%w[: )].include?(peek)
            advance if peek == ':'
            true
          end
        end

        def parse_class
          negated = false
          if peek == '^'
            advance
            negated = true
          end

          chars = []
          loop do
            raise Unsupported, 'unclosed class' if @index >= @chars.length

            char = advance
            break if char == ']'

            if char == '[' && peek == ':'
              chars.concat(posix_class)
            elsif char == '\\'
              chars.concat(class_escape(advance))
            elsif peek == '-' && !chars.empty? && @chars[@index + 1] && @chars[@index + 1] != ']'
              advance # '-'
              chars.concat((char..advance).to_a)
            else
              chars << char
            end
          end

          chars = RegexSynthesizer.negate(chars) if negated
          char_node(chars.uniq)
        end

        def posix_class
          advance # ':'
          name = +''
          name << advance while @index < @chars.length && peek != ':'
          raise Unsupported, 'bad posix class' unless peek == ':'

          advance
          raise Unsupported, 'bad posix class' unless peek == ']'

          advance
          expanded = POSIX_CLASSES[name]
          raise Unsupported, "unknown posix class #{name}" unless expanded

          expanded
        end

        def class_escape(char)
          return [parse_hex_char] if char == 'x'
          raise Unsupported, 'unicode property' if %w[p P].include?(char)

          CLASS_ESCAPES.fetch(char) { [char] }
        end

        def parse_escape
          char = advance
          return node(:empty) if ZERO_WIDTH.include?(char)
          return char_node(CLASS_ESCAPES[char]) if CLASS_ESCAPES.key?(char)
          return char_node([parse_hex_char]) if char == 'x'

          raise Unsupported, 'unicode property' if %w[p P].include?(char)
          raise Unsupported, 'backreference' if char.match?(/[1-9k]/)

          node(:literal, char)
        end

        def parse_hex_char
          hex = +''
          raise Unsupported, 'wide hex escape' if peek == '{'

          2.times { hex << advance }
          raise Unsupported, 'bad hex escape' unless hex.match?(/\A[0-9a-fA-F]{2}\z/)

          hex.to_i(16).chr
        end

        def char_node(chars)
          raise Unsupported, 'empty class' if chars.empty?

          node(:class, chars)
        end
      end
    end
  end
end
