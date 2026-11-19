# frozen_string_literal: true

module FactoryBakery
  module RegexGeneration
    module Handlers
      # Nodes that compose other nodes: sequences and groups, captures,
      # alternation, conditionals, backreferences and subexpression calls.
      module Structure
        private

        # Each child gets the window left over after its predecessors and
        # before its successors, so length hints steer the whole sequence.
        def render_sequence(node, window)
          tails = @plan.tails(node)
          start = @out.length
          node.expressions.each_with_index do |child, index|
            render(child, window.shift(@out.length - start, tails[index]))
          end
        end

        def render_capture(node, window)
          start = @out.length
          render_sequence(node, window)
          @captures[node] = @out[start..]
        end

        # Uniform among the branches that can still fit the window. Inside a
        # subexpression call branches that cannot recurse are preferred, so a
        # recursive pattern terminates instead of unfolding to the limit.
        def render_alternation(node, window)
          fitting = preferring(node.expressions) { |branch| window.admits?(@plan.range(branch)) }
          terminating = @call_depth.positive? ? preferring(fitting) { |b| @plan.range(b).last.finite? } : fitting
          render(sample(terminating), window)
        end

        def preferring(candidates, &)
          preferred = candidates.select(&)
          preferred.empty? ? candidates : preferred
        end

        # The branch matching whether the group has captured so far.
        def render_conditional(node, window)
          captured = @captures.key?(node.condition.referenced_expression)
          branches = node.branches
          [captured ? branches.first : branches[1]].compact.each { |branch| render(branch, window) }
        end

        # A group that never captured makes the backreference unmatchable.
        def render_backref(node, _window)
          text = @captures[node.referenced_expression]
          abort! if text.nil?

          emit_free(text)
        end

        # `\g<name>` renders the target group again (without its quantifier).
        def render_call(node, window)
          abort! if @call_depth >= Limits::MAX_CALL_DEPTH

          @call_depth += 1
          dispatch(node.referenced_expression, window)
          @call_depth -= 1
        end
      end
    end
  end
end
