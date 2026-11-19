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

      # Returns a candidate within `window` (best effort) or nil.
      def call(window)
        @output_cap = [Limits::MAX_OUTPUT_LENGTH, window.lo].max
        catch(ABORT) do
          render(@plan.root, window.capped(@output_cap))
          emit(@prefix)
          @out
        end
      end

      private

      def render(node, window)
        step!
        enter!
        quantifier = node.quantifier
        quantifier ? repeat(node, quantifier, window) : dispatch(node, window)
        @depth -= 1
      end

      def dispatch(node, window)
        send(@plan.renderer(node), node, window)
      end

      def repeat(node, quantifier, window)
        child_range = @plan.base_range(node)
        count = repeat_count(node, quantifier, child_range, window)
        start = @out.length
        count.times do |index|
          step!
          remaining = count - index - 1
          rest = child_range.map { |bound| bound.zero? || remaining.zero? ? 0 : bound * remaining }
          dispatch(node, window.shift(@out.length - start, rest))
        end
      end

      # How many repetitions to emit: the quantifier's range, narrowed so the
      # window can still be met, and at most MAX_REPEAT beyond the minimum
      # unless the window asks for more. Inside a subexpression call the
      # minimum is used so recursion bottoms out; while a lookahead text is
      # pending, a character class repeats exactly as long as it can follow it.
      def repeat_count(node, quantifier, child_range, window)
        low, high = repeat_bounds(quantifier, child_range, window)
        return low if @call_depth.positive?

        followed = pending_run(node)
        followed.positive? ? followed.clamp(low, high) : low + @random.rand(high - low + 1)
      end

      # [fewest, most] repetitions: at least what the window needs (capped by
      # the quantifier), at most what it allows, MAX_REPEAT past the minimum.
      def repeat_bounds(quantifier, child_range, window)
        upper = quantifier.max.negative? ? Float::INFINITY : quantifier.max
        low = [[quantifier.min, repetitions_needed(child_range.last, window)].max, upper].min
        allowed = [upper, repetitions_allowed(child_range.first, window)].min
        [low, [[allowed, quantifier.min + Limits::MAX_REPEAT].min.floor, low].max]
      end

      def repetitions_needed(child_max, window)
        child_max.zero? ? 0 : window.lo.fdiv(child_max).ceil
      end

      def repetitions_allowed(child_min, window)
        child_min.zero? ? Float::INFINITY : window.hi.fdiv(child_min)
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
