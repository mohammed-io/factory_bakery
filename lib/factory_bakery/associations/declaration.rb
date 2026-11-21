# frozen_string_literal: true

module FactoryBakery
  module Associations
    # A single recorded `association` call. Stored in core's per-plugin
    # declaration bucket and evaluated after the owner is instantiated, so the
    # declared traits, count, factory and overrides can be forwarded to each
    # child bake (or the owner block can receive the finished owner).
    Declaration = Struct.new(:name, :traits, :factory, :child_count, :overrides, :block, :strategy, :persist,
                             keyword_init: true)
  end
end
