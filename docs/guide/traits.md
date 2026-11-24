# Traits

A trait is a named set of declarations inside a definition. You apply it by name when you bake.

```ruby
FactoryBakery.define(User) do
  name { 'Ada' }

  trait :admin do
    role { 'admin' }
  end

  trait :vip do
    role  { 'vip' }
    level { 'gold' }
  end
end
```

```ruby
FactoryBakery.bake(User)                          # base definition
FactoryBakery.bake(User, :admin)                  # base + :admin
FactoryBakery.bake(User, :admin, :vip)            # role is 'vip': later traits win
FactoryBakery.bake(User, :admin, name: 'Grace')   # overrides beat every trait
```

On a recipe, you can pass traits as arguments or chain them in the order you want to apply them.

```ruby
FactoryBakery.recipe(User, :admin).vip.bake
FactoryBakery.recipe(User).trait(:admin, :vip).bake!
```

Use `.trait(:name)` for a name that collides with a recipe method, such as `:bake`, `:bake!` or `:trait`. An undeclared chained trait raises the same error as a trait passed to `bake` when you finish the recipe.

## Rules

- Traits are applied **after** the base declarations, in the order you list them. For the same attribute, the last one wins.
- A trait can contain anything a definition can: attribute blocks, `skip`, `initialize_with`, and `association` (with the plugin loaded).
- A later trait that redeclares an association replaces the earlier declaration. The same holds for `skip`: a later trait value replaces an earlier omission, and a later `skip` replaces an earlier value.
- A call-site override suppresses every declaration in its [alias group](overrides-and-precedence.md#alias-groups) before any block runs.
- Traits are local to one definition. There are no global traits.
- A trait cannot call another trait. Naming one inside a trait body is read as an attribute declaration with no block, which is ignored without error. Repeat the declarations, or pass both traits at the call site.
- Only the traits of the **bake target's own definition** are known. A trait name that definition lacks raises:

```
Trait :nope is not declared for User
```

This also happens for a class with no definition at all.

## Traits and associations

Traits listed on an `association` declaration are passed to the child's bake:

```ruby
association :author, :admin    # bakes the author with the :admin trait of its definition
```

The trait must exist in the **child's** definition. `strategy: :reuse_non_unique` cannot be combined with traits on a `belongs_to` and raises `ArgumentError`:

```
traits cannot be combined with strategy: :reuse_non_unique on User#editor
```

See [Associations](associations.md).

## Traits are not enums

If a state is a real enum or `inclusion:` list, inference already picks a valid member. Add a trait only for a state a test needs on purpose, such as `:published` or `:expired`.
