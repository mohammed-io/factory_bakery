# Types (Sorbet)

The gem ships Sorbet signatures for `bake`, `bake!`, and `recipe` in [`rbi/factory_bakery.rbi`](../../rbi/factory_bakery.rbi). The type of the baked record follows the target class.

```ruby
user = FactoryBakery.bake(User)          # User
FactoryBakery.bake!(Account, :admin)     # Account
FactoryBakery.bake(User) { |record| record.name }   # record is a User
user.nope                                # Sorbet: method `nope` does not exist on `User`
```

To install the signatures, copy the RBI into `sorbet/rbi/shims/` in your project.

## What is and is not checked

| Part | Checked |
| --- | --- |
| Return type for a class target | yes, the instance type of that class |
| Block argument | yes, same type |
| Symbol target (`bake(:admin_user)` or `recipe(:admin_user).bake`) | The baked record and block argument are `T.untyped`. Sorbet cannot know the class of a registered factory. |
| Trait names | no |
| `fill_optional:`, `validate:`, attribute overrides | no |

The module-level signatures use overloads for class and symbol targets. RBI overloads cannot declare keyword arguments, so those signatures accept traits and keywords as untyped arguments. The recipe's finishing methods also accept untyped keyword values. See [Definitions](definitions.md#declaring-an-attribute-the-model-does-not-have) for what happens to an unknown override at runtime.

## `recipe`: the same bake, written as a chain

```ruby
admin = FactoryBakery.recipe(User, :admin)
admin.bake(name: 'Ada')      # unsaved User
admin.bake!(name: 'Grace')   # saved User
FactoryBakery.recipe(User).trait(:admin, :verified).bake!  # saved User
```

A recipe is frozen and reusable. With the same target, traits, overrides, and seed at the same point in the bake sequence, the recipe and the equivalent module call generate the same values. When both the recipe and its `bake` or `bake!` call provide an override for the same key, the finishing call wins.

At runtime, you can chain traits with `FactoryBakery.recipe(User).admin.verified.bake!`. An undeclared trait raises `Trait :name is not declared for User` when the recipe is finished. Use `.trait(:name)` for a trait named `bake`, `bake!`, or `trait`.

With the shipped signatures, `FactoryBakery.recipe(User)` is a `FactoryBakery::Recipe[User]`. Both `bake` and `bake!` return a `User`. If you pass a block, it also receives a `User`. In Sorbet-checked code, pass trait names as arguments to `recipe` or `.trait`. The RBI has no signatures for dynamic trait methods such as `.admin`.
