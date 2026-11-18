# frozen_string_literal: true

module FactoryBakery
  module Associations
    # A single recorded `association` call. Stored in core's per-plugin
    # declaration bucket and evaluated after the owner is instantiated, so the
    # declared traits, factory and overrides can be forwarded to the child bake.
    Declaration = Struct.new(:name, :traits, :factory, :overrides, :block, keyword_init: true)
  end
end
