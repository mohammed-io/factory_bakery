# typed: strict
# frozen_string_literal: true

# Sorbet signatures for FactoryBakery's public bake API.
#
# `bake` and `bake!` return an instance of the class passed as the first
# argument, so `FactoryBakery.bake(User)` is typed as `User` (and a block
# receives a `User`). A symbol names a registered factory
# (`FactoryBakery.define(:admin, klass: User)`), whose class Sorbet cannot
# know, so that form returns `T.untyped`.
#
# Traits and keyword arguments (`fill_optional:`, `validate:`, attribute
# overrides) travel in `args` and are not type checked: an RBI overload cannot
# declare keyword arguments, and one generic signature cannot return the
# class's type for a class and `T.untyped` for a symbol.
#
# Copy this file into your project's `sorbet/rbi/shims/`. For `recipe`, also
# copy factory_bakery_recipe.rbi or use the Tapioca DSL compiler.
# In Tapioca, exclude factory_bakery from `gem` generation to use these shims.
module FactoryBakery
  # Tapioca can record this internal extension in its ActiveRecord gem RBI.
  module ActiveRecordMapper
    # Hook that flushes the mapper cache when the schema is reloaded.
    module SchemaReload; end
  end

  sig do
    type_parameters(:Model)
      .params(
        target: T::Class[T.type_parameter(:Model)],
        args: T.untyped,
        blk: T.nilable(T.proc.params(record: T.type_parameter(:Model)).void)
      )
      .returns(T.type_parameter(:Model))
  end
  sig do
    params(target: Symbol, args: T.untyped, blk: T.nilable(T.proc.params(record: T.untyped).void))
      .returns(T.untyped)
  end
  def self.bake(target, *args, &blk); end

  # Same typing as `bake`; the record is saved.
  sig do
    type_parameters(:Model)
      .params(
        target: T::Class[T.type_parameter(:Model)],
        args: T.untyped,
        blk: T.nilable(T.proc.params(record: T.type_parameter(:Model)).void)
      )
      .returns(T.type_parameter(:Model))
  end
  sig do
    params(target: Symbol, args: T.untyped, blk: T.nilable(T.proc.params(record: T.untyped).void))
      .returns(T.untyped)
  end
  def self.bake!(target, *args, &blk); end

  sig { params(target: T.any(T::Class[T.untyped], Symbol)).returns(T::Array[Symbol]) }
  def self.trait_names(target); end

  # A recipe returns and yields the model it was created for.
  class Recipe
    extend T::Generic

    Model = type_member

    sig { params(more: T.untyped, blk: T.nilable(T.proc.params(record: Model).void)).returns(Model) }
    def bake(**more, &blk); end

    sig { params(more: T.untyped, blk: T.nilable(T.proc.params(record: Model).void)).returns(Model) }
    def bake!(**more, &blk); end

    sig { params(names: Symbol).returns(T.self_type) }
    def trait(*names); end
  end
end
