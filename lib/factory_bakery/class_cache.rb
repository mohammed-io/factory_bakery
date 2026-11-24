# frozen_string_literal: true

module FactoryBakery
  # Stores per-class facts, one instance variable per fact, so they can be
  # cleared when a schema changes.
  #
  # The instance variable NAMES are the cache keys, defined once as the
  # frozen Symbol constants below: this module owns the list of names and
  # all invalidation, and every call site stores its fact under the constant
  # it declares. A hit in `fetch` or `table` is a single
  # `instance_variable_get` and a nil check -- the class is asked dozens of
  # times per bake, so the hot path allocates nothing -- and a class that is
  # reloaded loses the variables with it.
  #
  # A miss computes outside any lock (a computation may fetch other facts of
  # the same class) and publishes under the invalidation mutex only when no
  # `clear` happened while it ran: `clear` and `clear_all` bump an epoch
  # counter, and the epoch is re-checked where the bump happens, so a
  # computation that started before the bump must not re-publish its stale
  # value. Two threads that miss together both compute; the first to store
  # wins, which is harmless because the facts are pure functions of the class.
  #
  # A frozen class is never written to, and `fetch` recomputes on every call
  # for one frozen before anything was cached. A class frozen after being
  # cached keeps its facts -- instance variables cannot be removed after
  # freezing -- which is acceptable because a frozen model class cannot be
  # baked anyway.
  module ClassCache
    CONSTRAINTS = :@factory_bakery_constraints
    RECORD_DEPENDENT = :@factory_bakery_record_dependent
    UNIVERSE = :@factory_bakery_universe
    GUARD_COLUMNS = :@factory_bakery_guard_columns
    GUARD_COLUMNS_UNTIMED = :@factory_bakery_guard_columns_untimed
    ALIAS_GROUPS = :@factory_bakery_alias_groups
    UNIQUE_INDEX_GROUPS = :@factory_bakery_unique_index_groups
    UNIQUE_INDEX_COLUMNS = :@factory_bakery_unique_index_columns
    JSON_TEXT_COLUMNS = :@factory_bakery_json_text_columns
    UNIQUENESS_VALIDATORS = :@factory_bakery_uniqueness_validators
    UNIQUENESS_BATCH = :@factory_bakery_uniqueness_batch
    REFLECTIONS = :@factory_bakery_reflections
    ASSOCIATIONS = :@factory_bakery_associations
    FILLERS = :@factory_bakery_fillers
    SEQUEL_CACHE = :@factory_bakery_sequel_cache
    MAPPER = :@factory_bakery_mapper

    @mutex = Mutex.new
    @epoch = 0

    class << self
      def fetch(klass, ivar)
        value = klass.instance_variable_get(ivar)
        return value unless value.nil?

        epoch = @epoch
        value = yield
        return value if klass.frozen?

        # Publish under the invalidation mutex, with the epoch re-checked
        # where `clear` bumps it: a computation that started before a clear
        # must not re-publish its stale value after the epoch check has
        # already passed.
        @mutex.synchronize do
          return value if @epoch != epoch

          klass.instance_variable_get(ivar) || klass.instance_variable_set(ivar, value)
        end
      rescue FrozenError
        # The class was frozen between the check and the write. The computed
        # value is still returned, unpublished: `fetch` recomputes it next
        # time, as it does for a class frozen all along.
        value
      end

      # A per-class Hash for callers that keep a keyed map (a frozen class
      # gets a throwaway one, so writes to it simply do not stick).
      def table(klass, ivar)
        klass.instance_variable_get(ivar) || create_table(klass, ivar)
      end

      # Publishes a computed value that `fetch` left unstored (the mapper
      # registry replaces a stale `[generation, mapper]` pair with a fresh
      # one). Returns the value.
      def store(klass, ivar, value)
        klass.instance_variable_set(ivar, value) unless klass.frozen?
        value
      rescue FrozenError
        value
      end

      def clear(klass)
        @mutex.synchronize do
          @epoch += 1
          drop(klass)
        end
      end

      # Only runs on a code reload or an explicit `FactoryBakery.reset_cache!`,
      # never during a bake.
      def clear_all
        @mutex.synchronize do
          @epoch += 1
          ObjectSpace.each_object(Class) { |klass| drop(klass) }
        end
      end

      private

      def create_table(klass, ivar)
        return {} if klass.frozen?

        klass.instance_variable_get(ivar) || klass.instance_variable_set(ivar, {})
      rescue FrozenError
        {}
      end

      # Never raises for a frozen class, so `clear_all` keeps going through
      # every class. A frozen class keeps its facts (its instance variables
      # cannot be removed after freezing), which is acceptable because a
      # frozen model class cannot be baked anyway.
      def drop(klass)
        return if klass.frozen?

        klass.instance_variables.each do |name|
          klass.remove_instance_variable(name) if name.start_with?('@factory_bakery_')
        end
      end
    end
  end
end
