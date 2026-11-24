# typed: strict
# frozen_string_literal: true

# Copy this file alongside factory_bakery.rbi for the static recipe signatures.
# Omit this file when using the Tapioca DSL compiler for FactoryBakery.
module FactoryBakery
  # `recipe(User, :admin)` is a bake waiting for its finishing call.
  sig do
    type_parameters(:Model)
      .params(target: T::Class[T.type_parameter(:Model)], args: T.untyped)
      .returns(FactoryBakery::Recipe[T.type_parameter(:Model)])
  end
  sig { params(target: Symbol, args: T.untyped).returns(FactoryBakery::Recipe[T.untyped]) }
  def self.recipe(target, *args); end
end
