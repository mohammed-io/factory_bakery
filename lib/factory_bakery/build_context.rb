# frozen_string_literal: true

module FactoryBakery
  # Records the bake calls currently in flight. Every public `bake` pushes the
  # resolved class and pops it in an `ensure`, so a declaration block that bakes
  # again sees the classes above it and runaway recursion becomes a clear error
  # instead of a SystemStackError.
  #
  # The stack is stored fiber-locally (Fiber[] storage is inherited by child
  # fibers but never shared between threads). The value is replaced rather than
  # mutated, so a child fiber that inherited a parent's context can never mutate
  # the parent's stack.
  class BuildContext
    STORAGE_KEY = :factory_bakery_build_context

    class << self
      def current
        Fiber[STORAGE_KEY] ||= new([].freeze)
      end

      def push(klass)
        previous = current
        limit = FactoryBakery.max_bake_depth
        next_depth = previous.depth + 1

        if next_depth > limit
          path = (previous.path + [klass]).map { |entry| class_name(entry) }.join(' -> ')
          raise NestingTooDeepError,
                "bake nesting exceeded max_bake_depth (#{limit}): #{path}"
        end

        Fiber[STORAGE_KEY] = previous.append(klass)
        yield
      ensure
        Fiber[STORAGE_KEY] = previous
      end

      private

      def class_name(klass)
        klass.respond_to?(:name) && klass.name ? klass.name : klass.to_s
      end
    end

    attr_reader :path

    def initialize(path)
      @path = path.freeze
    end

    def depth
      @path.length
    end

    def append(klass)
      self.class.new(@path + [klass])
    end
  end
end
