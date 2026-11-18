# frozen_string_literal: true

module FactoryBakery
  # Discovers counter-cache columns on an ActiveRecord model from Rails'
  # reflection metadata. Rails maintains these columns itself, so heuristics
  # must never invent a value for them.
  #
  # The authoritative column name lives on the child's +belongs_to+ reflection
  # (e.g. +belongs_to :post, counter_cache: :unusual_tally+). The parent's
  # +has_many+ reflection only knows the default name, so custom columns are
  # found by following the association to the child class. Only the public
  # +has_cached_counter?+ / +counter_cache_column+ API is used; both exist on
  # the reflections of Rails 7.1 through 8.x.
  class CounterCacheDetector
    def initialize(model_class)
      @model_class = model_class
    end

    # @return [Array<String>] names of counter-cache columns on the model
    def column_names
      return [] unless detectable?

      child_reflections.flat_map { |reflection| columns_for(reflection) }.compact.uniq
    end

    private

    def detectable?
      @model_class.respond_to?(:reflect_on_all_associations) &&
        @model_class.respond_to?(:columns_hash)
    end

    def child_reflections
      @model_class.reflect_on_all_associations(:has_many) +
        @model_class.reflect_on_all_associations(:has_one)
    end

    def columns_for(reflection)
      [declared_on_parent(reflection), *declared_on_child(reflection)]
    end

    # +counter_cache+ given on the has_many/has_one itself.
    def declared_on_parent(reflection)
      counter_column(reflection) if cached_counter?(reflection)
    end

    # +counter_cache+ given on the child's belongs_to, which is the common
    # case and the only place a custom column name is recorded.
    def declared_on_child(reflection)
      child = associated_class(reflection)
      return [] unless child.respond_to?(:reflect_on_all_associations)

      child.reflect_on_all_associations(:belongs_to).filter_map do |inverse|
        next unless points_back_to_model?(inverse) && cached_counter?(inverse)

        counter_column(inverse)
      end
    end

    def points_back_to_model?(inverse)
      return false unless inverse.respond_to?(:polymorphic?) && !inverse.polymorphic?
      return false unless inverse.respond_to?(:klass)

      inverse.klass == @model_class
    rescue StandardError
      false
    end

    # Reflection introspection is best-effort: exotic associations (e.g.
    # has_many :through) can raise here. That must never break baking.
    def associated_class(reflection)
      reflection.klass
    rescue StandardError
      nil
    end

    def cached_counter?(reflection)
      reflection.respond_to?(:has_cached_counter?) && reflection.has_cached_counter?
    rescue StandardError
      false
    end

    def counter_column(reflection)
      reflection.counter_cache_column&.to_s if reflection.respond_to?(:counter_cache_column)
    rescue StandardError
      nil
    end
  end
end
