# typed: strict

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
# Copy this file into your project's `sorbet/rbi/shims/`.
module FactoryBakery
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
end
