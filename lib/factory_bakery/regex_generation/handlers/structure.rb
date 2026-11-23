# frozen_string_literal: true

module FactoryBakery
  module RegexGeneration
    module Handlers
      # Nodes that compose other nodes: sequences and groups, captures,
      # alternation, conditionals, backreferences and subexpression calls.
      module Structure
        private

        # Each child gets the length bounds left over after its predecessors and
        # before its successors, so length hints steer the whole sequence.
        def render_sequence(node, low, high)
          tails = @plan.tails(node)
          start = @out.length
          node.expressions.each_with_index do |child, index|
            done = @out.length - start
            tail = tails[index]
            child_low = low - done - tail.last
            render(child, child_low.negative? ? 0 : child_low, high - done - tail.first)
          end
        end

        def render_capture(node, low, high)
          start = @out.length
          render_sequence(node, low, high)
          @captures[node] = @out[start..]
        end

        # Uniform among the branches that can still fit the length bounds.
        # Inside a subexpression call branches that cannot recurse are
        # preferred, so a recursive pattern terminates instead of unfolding to
        # the limit.
        def render_alternation(node, low, high)
          fitting = preferring(node.expressions) { |branch| admits?(@plan.range(branch), low, high) }
          terminating = @call_depth.positive? ? preferring(fitting) { |b| @plan.range(b).last.finite? } : fitting
          render(sample(terminating), low, high)
        end

        # Whether a node that can produce `range` ([min, max]) can fit.
        def admits?(range, low, high)
          range.first <= high && range.last >= low
        end

        def preferring(candidates, &)
          preferred = candidates.select(&)
          preferred.empty? ? candidates : preferred
        end

        # The branch matching whether the group has captured so far.
        def render_conditional(node, low, high)
          captured = @captures.key?(node.condition.referenced_expression)
          branches = node.branches
          [captured ? branches.first : branches[1]].compact.each { |branch| render(branch, low, high) }
        end

        # A group that never captured makes the backreference unmatchable.
        def render_backref(node, _low, _high)
          text = @captures[node.referenced_expression]
          abort! if text.nil?

          emit_free(text)
        end

        # `\g<name>` renders the target group again (without its quantifier).
        def render_call(node, low, high)
          abort! if @call_depth >= Limits::MAX_CALL_DEPTH

          @call_depth += 1
          dispatch(node.referenced_expression, low, high)
          @call_depth -= 1
        end
      end
    end
  end
end
