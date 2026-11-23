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
      # The table is captured before the block runs, so a `clear` that happens
      # while a miss is in flight detaches the table: the late result lands in
      # the table that was current when the computation started, never in the
      # fresh one a later `fetch` reads.
      #
      # A hit is one instance-variable read and one Hash lookup: the class is
      # asked dozens of times per bake, so the hit path allocates nothing.
      #
      # A frozen class is never served from or written to the cache: its table
      # can never go stale, because no value computed for it is ever stored.
      def fetch(klass, key)
        return yield if klass.frozen?

        store = klass.instance_variable_get(IVAR)
        value = store ? store.fetch(key, MISSING) : MISSING
        return value unless value.equal?(MISSING)

        store ||= store_for(klass)
        value = yield
        store.key?(key) ? store[key] : (store[key] = value)
      end

      # A per-class Hash for callers that keep a keyed map (a frozen class gets
      # a throwaway one, so writes to it simply do not stick). Like `fetch`, a
      # frozen class is never served from or written to the cache.
      def table(klass, key)
        return {} if klass.frozen?

        store = klass.instance_variable_get(IVAR)
        hit = store && store[key]
        return hit if hit

        fetch(klass, key) { {} }
      end

      # Leaves a stale entry in the weak map on purpose: a WeakMap cannot
      # delete (its `delete` arrived in Ruby 3.3), and an entry whose class no
      # longer holds a table is inert. `clear_all` swaps the map wholesale.
      def clear(klass)
        @mutex.synchronize { drop(klass) }
      end

      def clear_all
        @mutex.synchronize do
          @classes.each_key { |klass| drop(klass) }
          @classes = ObjectSpace::WeakMap.new
        end
      end

      private

      # Never raises for a frozen class, so `clear_all` keeps going through
      # every class. An unfrozen class loses its instance variable, which
      # detaches any table a computation in flight still holds; a frozen class
      # that was cached before it was frozen can only have its table emptied
      # in place, since instance variables cannot be removed after freezing.
      def drop(klass)
        if klass.frozen?
          klass.instance_variable_get(IVAR)&.clear
        elsif klass.instance_variable_defined?(IVAR)
          klass.remove_instance_variable(IVAR)
        end
      end

      def store_for(klass)
        klass.instance_variable_get(IVAR) || @mutex.synchronize do
          klass.instance_variable_get(IVAR) || klass.instance_variable_set(IVAR, {}).tap { @classes[klass] = true }
        end
      end
    end
  end
end
