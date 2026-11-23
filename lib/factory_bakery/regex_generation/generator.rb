# frozen_string_literal: true

module FactoryBakery
  module RegexGeneration
    # Builds one candidate string by walking a Plan's tree. A generator is a
    # single-use object: the output buffer, captures and counters belong to
    # one attempt. Every bound in Limits abandons the attempt (`call` then
    # returns nil) rather than looping or truncating.
    class Generator
      include Handlers::Characters
      include Handlers::Structure
      include Handlers::Assertions

      ABORT = :regex_generation_abort

      def initialize(plan, random)
        @plan = plan
        @random = random
        @encoding = plan.universe.encoding
        @out = String.new(encoding: @encoding)
        @captures = {}.compare_by_identity
        @steps = 0
        @depth = 0
        @call_depth = 0
        @prefix = ''
        @word_next = nil
      end

      # Returns a candidate of length `low..high` (best effort) or nil.
      def call(low, high)
        @output_cap = [Limits::MAX_OUTPUT_LENGTH, low].max
        catch(ABORT) do
          render(@plan.root, low, [high, @output_cap].min)
          emit(@prefix)
          @out
        end
      end

      private

      def render(node, low, high)
        step!
        enter!
        quantifier = node.quantifier
        quantifier ? repeat(node, quantifier, low, high) : dispatch(node, low, high)
        @depth -= 1
      end

      def dispatch(node, low, high)
        send(@plan.renderer(node), node, low, high)
      end

      def repeat(node, quantifier, low, high)
        child_min, child_max = @plan.base_range(node)
        count = repeat_count(node, quantifier, @plan.base_range(node), low, high)
        start = @out.length
        (count - 1).downto(0) do |remaining|
          step!
          done = @out.length - start
          dispatch(node, shift_low(low, done, tail(child_max, remaining)), high - done - tail(child_min, remaining))
        end
      end

      # The characters the nodes after this one still need: `bound` per
      # repetition, nothing once none are left (an infinite bound times zero
      # would be undefined).
      def tail(bound, remaining)
        remaining.zero? ? 0 : bound * remaining
      end

      # The lowest length a node may still produce: what is left of `low` once
      # `done` characters are out and the nodes after it still need `tail_max`.
      def shift_low(low, done, tail_max)
        left = low - done - tail_max
        left.negative? ? 0 : left
      end

      # How many repetitions to emit: the quantifier's range, narrowed so the
      # length bounds can still be met, and at most MAX_REPEAT beyond the
      # minimum unless the bounds ask for more. Inside a subexpression call the
      # minimum is used so recursion bottoms out; while a lookahead text is
      # pending, a character class repeats exactly as long as it can follow it.
      def repeat_count(node, quantifier, child_range, low, high)
        fewest, most = repeat_bounds(quantifier, child_range, low, high)
        return fewest if @call_depth.positive?

        followed = pending_run(node)
        followed.positive? ? followed.clamp(fewest, most) : fewest + @random.rand(most - fewest + 1)
      end

      # [fewest, most] repetitions: at least what the length bounds need (capped
      # by the quantifier), at most what they allow, MAX_REPEAT past the minimum.
      def repeat_bounds(quantifier, child_range, low, high)
        upper = quantifier.max.negative? ? Float::INFINITY : quantifier.max
        fewest = [[quantifier.min, repetitions_needed(child_range.last, low)].max, upper].min
        allowed = [upper, repetitions_allowed(child_range.first, high)].min
        [fewest, [[allowed, quantifier.min + Limits::MAX_REPEAT].min.floor, fewest].max]
      end

      def repetitions_needed(child_max, low)
        child_max.zero? ? 0 : low.fdiv(child_max).ceil
      end

      def repetitions_allowed(child_min, high)
        child_min.zero? ? Float::INFINITY : high.fdiv(child_min)
      end

      # Leading characters of the pending lookahead text a character class
      # accepts.
      def pending_run(node)
        return 0 unless @plan.renderer(node) == :render_pool && !@prefix.empty?

        accepted = @plan.pool(node).flatten
        @prefix.each_char.take_while { |char| accepted.include?(char) }.size
      end

      def step!
        @steps += 1
        abort! if @steps > Limits::MAX_STEPS
      end

      def enter!
        @depth += 1
        abort! if @depth > Limits::MAX_DEPTH
      end

      def abort!
        throw ABORT
      end

      def emit(text)
        @out << text
        abort! if @out.length > @output_cap
      end

      # Emission that does not follow a pending lookahead text.
      def emit_free(text)
        @prefix = ''
        emit(text)
      end

      def sample(array)
        array[@random.rand(array.size)]
      end
    end
  end
end
