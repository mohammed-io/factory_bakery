# frozen_string_literal: true

module FactoryBakery
  module RegexGeneration
    # Codepoints spelled by a literal or escape-sequence node (`a`, `\x41`,
    # `\u{1F600 41}`, `\012`, ...). regexp_parser resolves control and meta
    # escapes (`\cA`, `\M-a`) to the byte they stand for.
    module Codepoints
      def self.of(node)
        return node.text.codepoints if node.type == :literal

        node.respond_to?(:codepoints) ? node.codepoints : [node.codepoint]
      end
    end
  end
end
