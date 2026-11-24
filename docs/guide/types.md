# Types (Sorbet)

There are two levels. The static signatures need nothing but a file copy and type the baked record by its class. The opt-in Tapioca plugin goes further and generates, for each model with a definition, trait methods and type-checked override keywords on the `recipe` form.

## Static signatures

The gem ships Sorbet signatures for `bake`, `bake!`, and `recipe` in [`rbi/factory_bakery.rbi`](../../rbi/factory_bakery.rbi) and [`rbi/factory_bakery_recipe.rbi`](../../rbi/factory_bakery_recipe.rbi). The type of the baked record follows the target class.

```ruby
user = FactoryBakery.bake(User)          # User
FactoryBakery.bake!(Account, :admin)     # Account
FactoryBakery.bake(User) { |record| record.name }   # record is a User
user.nope                                # Sorbet: method `nope` does not exist on `User`
```

To install, copy **both** RBI files into `sorbet/rbi/shims/` in your project.

| Part | Checked |
| --- | --- |
| Return type for a class target | yes, the instance type of that class |
| Block argument | yes, same type |
| Symbol target (`bake(:admin_user)` or `recipe(:admin_user).bake`) | The baked record and block argument are `T.untyped`. Sorbet cannot know the class of a registered factory. |
| Trait names | no |
| `fill_optional:`, `validate:`, attribute overrides | no |

The module-level signatures use overloads for class and symbol targets. RBI overloads cannot declare keyword arguments, so those signatures accept traits and keywords as untyped arguments. Sorbet has no way to derive keyword parameters from a generic type, which is why per-model checking needs generated code (below). See [Definitions](definitions.md#declaring-an-attribute-the-model-does-not-have) for what happens to an unknown override at runtime.

## `recipe`: the same bake, written as a chain

```ruby
admin = FactoryBakery.recipe(User, :admin)
admin.bake(name: 'Ada')      # unsaved User
admin.bake!(name: 'Grace')   # saved User
FactoryBakery.recipe(User).trait(:admin, :verified).bake!  # saved User
```

A recipe is frozen and reusable. With the same target, traits, overrides, and seed at the same point in the bake sequence, the recipe and the equivalent module call generate the same values. When both the recipe and its `bake` or `bake!` call provide an override for the same key, the finishing call wins.

At runtime, you can chain traits with `FactoryBakery.recipe(User).admin.verified.bake!`. An undeclared trait raises `Trait :name is not declared for User` when the recipe is finished. Use `.trait(:name)` for a trait named `bake`, `bake!`, or `trait`.

With the static signatures, `FactoryBakery.recipe(User)` is a `FactoryBakery::Recipe[User]`. Both `bake` and `bake!` return a `User`, and a block also receives a `User`. In Sorbet-checked code, pass trait names as arguments to `recipe` or `.trait`: the static RBI has no signatures for dynamic trait methods such as `.admin`.

## Per-model types with Tapioca (opt-in)

For Sorbet projects that use [Tapioca](https://github.com/Shopify/tapioca), a compiler shipped with the gem generates types for every ActiveRecord model that has a registered definition.

### Setup

1. Require the opt-in during application boot, and make sure your definitions are loaded before Tapioca runs:

   ```ruby
   require 'factory_bakery/sorbet'
   ```

2. Copy only `factory_bakery.rbi` into `sorbet/rbi/shims/`. Do not copy `factory_bakery_recipe.rbi`: the generated file defines `recipe` itself, and two definitions of the same method are an error.
3. Add `factory_bakery` to `gem.exclude` in `sorbet/tapioca/config.yml`. Without it `tapioca gem` imports both shipped RBI files and the signatures are duplicated.
4. Run `bin/tapioca dsl`. To regenerate only this file, run `bin/tapioca dsl FactoryBakery`. Tapioca finds the compiler in the gem on its own; the output is `sorbet/rbi/dsl/factory_bakery.rbi`.

Run it again when a definition's traits or a model's columns change. Nothing runs at boot or during a bake: the compiler is loaded only by Tapioca, and requiring `factory_bakery` alone never loads Sorbet or Tapioca.

### What is generated

For each class with a definition, a recipe class exists in the RBI only:

```ruby
FactoryBakery.recipe(User).admin.bake(name: 'Ada', account: account)  # a User
FactoryBakery.recipe(User).admin.bake(name: 10)    # Sorbet: Expected T.nilable(String) but found Integer(10)
FactoryBakery.recipe(User).bake(naem: 'Ada')       # Sorbet: Unrecognized keyword argument naem
FactoryBakery.recipe(User).adimn                   # Sorbet: Method adimn does not exist
```

- Each declared trait is a method (autocompletion in an editor depends on Sorbet's language server; it has not been checked in an editor).
- `bake` and `bake!` take every column and association name as an optional keyword, typed from the schema, always `T.nilable`. Collection associations accept arrays. Both return the model, and a block receives the model.
- Still untyped: JSON and other unmapped columns, polymorphic association values, `fill_optional:`, and `validate:`.
- Still unchecked: positional trait names (`recipe(User, :admin)`), names passed to `.trait`, keywords on the initial `recipe(...)` call, and overrides on plain `bake(User, ...)`.

### Limits

- A symbol-only registration (`FactoryBakery.define(:admin_user, klass: User)`) adds the model's typed `bake`/`bake!` to that model's class recipe. The symbol factory's own traits stay on the symbol target, because a class definition and a symbol definition are independent at runtime. `recipe(:admin_user)` keeps an untyped model.
- Sorbet can select a registered parent's `T.class_of` overload for an unregistered subclass of that parent.
- Only ActiveRecord models are covered. Sequel and plain ActiveModel targets are skipped.
- Trait names come from `FactoryBakery.trait_names(User)`, which reads the declared trait names of a definition without running attribute value blocks or trait bodies.
