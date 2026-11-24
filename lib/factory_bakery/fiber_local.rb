# frozen_string_literal: true

module FactoryBakery
  # Per-fiber storage that child fibers do NOT inherit. `Fiber[]` storage is
  # inherited, which is right for a value that should follow work started
  # inside a bake (the random generator) but wrong for build state: a fiber or
  # thread started inside a bake is an independent unit of execution, so it
  # must not join the parent's graph while the parent runs, and must not keep
  # the parent's depth, bound record or options after the parent has finished.
  #
  # `Thread#[]` is exactly that: scoped to the current fiber, never inherited,
  # never shared between threads.
  module FiberLocal
    class << self
      def [](key)
        Thread.current[key]
      end

      def []=(key, value)
        Thread.current[key] = value
      end
    end
  end
end
