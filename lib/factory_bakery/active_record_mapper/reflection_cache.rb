# frozen_string_literal: true

module FactoryBakery
  module ActiveRecordMapper
    # Caches the reflection lists a bake asks for, on the model class itself.
    #
    # ActiveRecord memoizes its raw `reflections` hash, but
    # `reflect_on_all_associations` rebuilds a filtered array on every call. A
    # single bake asks for the belongs_to list several times (alias groups, FK
    # skip set, plugin heuristics, counter-cache detection) and the full list
    # again for persistence verification and :all collections. Keeping the
    # filtered arrays on the class removes that repeated work without a global
    # map: reloading a class drops its cache with it.
    module ReflectionCache
      class << self
        def belongs_to(model_class)
          cache_for(model_class)[:belongs_to] ||=
            model_class.reflect_on_all_associations(:belongs_to)
        end

        def many(model_class)
          cache_for(model_class)[:has_many] ||=
            model_class.reflect_on_all_associations(:has_many)
        end

        def one(model_class)
          cache_for(model_class)[:has_one] ||=
            model_class.reflect_on_all_associations(:has_one)
        end

        def all(model_class)
          cache_for(model_class)[:all] ||= model_class.reflect_on_all_associations
        end

        private

        def cache_for(model_class)
          model_class.instance_variable_get(:@factory_bakery_reflections) ||
            model_class.instance_variable_set(:@factory_bakery_reflections, {})
        end
      end
    end
  end
end
