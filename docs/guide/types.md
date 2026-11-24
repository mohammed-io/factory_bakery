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
