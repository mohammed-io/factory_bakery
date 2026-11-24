# Types (Sorbet)

The gem ships Sorbet signatures for `bake` and `bake!` in [`rbi/factory_bakery.rbi`](../../rbi/factory_bakery.rbi). They make the return type follow the first argument:

```ruby
user = FactoryBakery.bake(User)          # User
FactoryBakery.bake!(Account, :admin)     # Account
FactoryBakery.bake(User) { |record| record.name }   # record is a User
user.nope                                # Sorbet: method `nope` does not exist on `User`
```

Install: copy the file into `sorbet/rbi/shims/` in your project.

## What is and is not checked

| Part | Checked |
| --- | --- |
| Return type for a class target | yes, the instance type of that class |
| Block argument | yes, same type |
| Symbol target (`bake(:admin_user)`, a registered factory) | no, `T.untyped`: Sorbet cannot know which class a name maps to |
| Traits | no |
| `fill_optional:`, `validate:`, attribute overrides | no |

Traits and keyword arguments travel in one untyped splat because an RBI overload cannot declare keyword arguments, and one generic signature cannot return the class's type for a class and `T.untyped` for a symbol. A typo in an override name is therefore still silent (see [Definitions](definitions.md#declaring-an-attribute-the-model-does-not-have)).

## `recipe`: the same bake, written as a chain

```ruby
admin = FactoryBakery.recipe(User, :admin)   # a bake waiting for the rest
admin.bake(name: 'Ada')                      # == FactoryBakery.bake(User, :admin, name: 'Ada')
admin.bake!(name: 'Grace')                   # == FactoryBakery.bake!(User, :admin, name: 'Grace')
FactoryBakery.recipe(User).admin.verified.bake!   # traits can be chained too
```

A recipe is frozen, so one can be kept and reused. `recipe(...).bake` and `recipe(...).bake!` call the module's `bake` and `bake!` with the same traits and overrides, so both spellings produce the same record. Overrides given to the recipe and to `bake` are merged, the later ones winning.

A chained trait name that is not declared raises the usual `Trait :name is not declared` error when the recipe is finished. A trait named `bake`, `bake!` or `trait` is added with `recipe(User).trait(:bake)`.

With the shipped signatures, `FactoryBakery.recipe(User).bake` is typed as `User`, like `bake(User)`; traits and overrides are not checked.
