# frozen_string_literal: true

module FactoryBakery
  # Routes FFaker to the generator of the bake running in the current fiber.
  # FFaker's helpers (`FFaker::Random.rand`, the module helpers behind
  # `FFaker::Name` and friends) all draw through `FFaker::Random.rng`. This
  # hook is prepended to FFaker::Random's singleton class once, at load time:
  # inside a top-level bake `rng` answers with that bake's generator, so the
  # bake's values and FFaker's share one seeded stream, and outside a bake it
  # falls back to FFaker's own generator with `super`. FFaker's own seed and
  # generator are never written to, so two bakes that overlap in two fibers
  # or threads each draw from their own generator and nothing has to be
  # restored afterwards.
  module FfakerGenerator
    def rng
      Randomness.scope&.rng || super
    end
  end
end

FFaker::Random.singleton_class.prepend(FactoryBakery::FfakerGenerator) unless
  FFaker::Random.singleton_class.ancestors.include?(FactoryBakery::FfakerGenerator)
