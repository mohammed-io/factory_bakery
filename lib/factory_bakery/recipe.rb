# frozen_string_literal: true

module FactoryBakery
  # A bake with its target and traits (and, optionally, some overrides) already
  # given, waiting for the rest. Its `bake` finishes it unsaved and its `bake!`
  # saved, like the module methods of the same names:
  #
  #   admin = FactoryBakery.recipe(User, :admin)
  #   admin.bake(name: 'Ada')      # == FactoryBakery.bake(User, :admin, name: 'Ada')
  #   admin.bake!(name: 'Grace')   # == FactoryBakery.bake!(User, :admin, name: 'Grace')
  #
  # A Recipe is frozen and holds no state, so one can be kept and reused. It
  # adds no behavior of its own: they call FactoryBakery.bake and
  # FactoryBakery.bake! with the same traits and overrides, so both spellings
  # produce the same record.
  class Recipe
    # What a chained trait call may be spelled like. Anything else, and the
    # names of Recipe's own methods, add a trait through `trait(:name)`.
    TRAIT_NAME = /\A[a-z_][A-Za-z0-9_]*\z/

    # `recipe(User, :admin, name: 'Ada')`: the entry point, extended onto
    # FactoryBakery.
    module Entry
      def recipe(target, *traits, **overrides)
        Recipe.new(target, traits, overrides)
      end
    end

    attr_reader :target, :traits, :overrides

    def initialize(target, traits = [], overrides = {})
      @target = target
      @traits = traits.dup.freeze
      @overrides = overrides.dup.freeze
      freeze
    end

    # Overrides given here win over those the recipe already carries. Takes a
    # block like `bake` does.
    def bake(**more, &)
      FactoryBakery.bake(target, *traits, **overrides, **more, &)
    end

    def bake!(**more, &)
      FactoryBakery.bake!(target, *traits, **overrides, **more, &)
    end

    # More traits, applied after those already given, in the order added.
    def trait(*names)
      self.class.new(target, traits + names, overrides)
    end

    # `recipe(User).admin` adds the trait :admin. Whether the trait exists is
    # checked when the recipe is finished, by the same error a bake raises.
    # Not advertised through respond_to?: which names are traits is only known
    # once the definition has run.
    def method_missing(name, *args, &block) # rubocop:disable Style/MissingRespondToMissing
      return super unless args.empty? && block.nil? && TRAIT_NAME.match?(name)

      trait(name)
    end
  end
end
