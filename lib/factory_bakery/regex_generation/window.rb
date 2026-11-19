# frozen_string_literal: true

module FactoryBakery
  module RegexGeneration
    # The span of output lengths a node may still produce so that the whole
    # candidate lands inside the caller's length hints. `hi` may be infinite.
    Window = Struct.new(:lo, :hi) do
      # The window left for a node once `done` characters are out and the
      # nodes after it still need `rest` (a [min, max] pair) characters.
      def shift(done, rest)
        Window.new([lo - done - rest.last, 0].max, hi - done - rest.first)
      end

      # Whether a node that can produce `range` ([min, max]) can fit.
      def admits?(range)
        range.first <= hi && range.last >= lo
      end

      def cover?(length)
        length.between?(lo, hi)
      end

      def capped(cap)
        Window.new(lo, [hi, cap].min)
      end
    end

    Window::ANY = Window.new(0, Float::INFINITY)
  end
end
