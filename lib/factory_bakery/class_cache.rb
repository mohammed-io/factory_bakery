# frozen_string_literal: true

require 'objspace'

module FactoryBakery
  # Stores per-class facts so they can be cleared when a schema changes.
  module ClassCache
    IVAR = :@factory_bakery_class_cache
    MISSING = Object.new.freeze
    private_constant :MISSING

    @mutex = Mutex.new
    @classes = ObjectSpace::WeakMap.new

    class << self
      # The block runs outside the lock, because a computation may fetch other
      # facts of the same class (the attribute universe asks for the guard
      # columns) and the mutex is not reentrant. Two threads that miss together
      # both compute, and the first to store wins: the facts are pure functions
      # of the class, so the duplicate work is harmless.
      #
      # A hit is one instance-variable read and one Hash lookup: the class is
      # asked dozens of times per bake, so the hit path allocates nothing.
      def fetch(klass, key)
        store = klass.instance_variable_get(IVAR)
        value = store ? store.fetch(key, MISSING) : MISSING
        return value unless value.equal?(MISSING)
        return yield if klass.frozen?

        value = yield
        store = store_for(klass)
        store.key?(key) ? store[key] : (store[key] = value)
      end

      # A per-class Hash for callers that keep a keyed map (a throwaway one for
      # a frozen class, so writes to it simply do not stick).
      def table(klass, key)
        store = klass.instance_variable_get(IVAR)
        hit = store && store[key]
        return hit if hit
        return {} if klass.frozen?

        fetch(klass, key) { {} }
      end

      def clear(klass)
        @mutex.synchronize do
          drop(klass)
          @classes.delete(klass)
        end
      end

      def clear_all
        @mutex.synchronize do
          @classes.each_key { |klass| drop(klass) }
          @classes = ObjectSpace::WeakMap.new
        end
      end

      private

      def drop(klass)
        klass.remove_instance_variable(IVAR) if klass.instance_variable_defined?(IVAR)
      end

      def store_for(klass)
        klass.instance_variable_get(IVAR) || @mutex.synchronize do
          klass.instance_variable_get(IVAR) || klass.instance_variable_set(IVAR, {}).tap { @classes[klass] = true }
        end
      end
    end
  end
end
