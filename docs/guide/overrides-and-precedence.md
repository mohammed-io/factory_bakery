# Overrides and precedence

Every attribute value comes from one of these layers. The first layer that mentions the attribute wins.

| Rank | Layer | Example |
| --- | --- | --- |
| 1 | Call-site overrides | `bake(User, name: 'Grace')` |
| 2 | Traits, in the order given | `bake(User, :admin, :vip)` |
| 3 | Declarations and `skip`, in declaration order | `name { 'Ada' }` |
| 4 | Plugin values (association auto-build, attachments) | `required_only` builds a required parent |
| 5 | Heuristics | Inferred from validators and columns |

`initialize_with` values are applied when the object is constructed. Declarations and overrides assigned later replace them. Inference never overwrites them.

The same order, in one line:

> call-site overrides > traits > declarations (and `skip`) > plugin auto-build > heuristics

Keywords passed to a recipe and to its `bake` or `bake!` call merge into one set of call-site overrides. If both calls give the same key, the value from `bake` or `bake!` wins.

```ruby
user = FactoryBakery.recipe(User, name: 'Ada').bake(name: 'Grace')
user.name # => "Grace"
```

## Rules that follow from this

- **Only the winning declaration runs.** A block that loses is never evaluated. A block with a side effect (a `bake!` inside it) does nothing when an override replaces it.
- **An explicit `nil` wins.** `bake(User, bio: nil)` calls `bio = nil`. This is also how you opt an edge out: `bake(Post, user: nil)`.
- **`skip` is a declaration.** It beats heuristics and plugins. A trait or a call-site value beats it.
- **Overrides are not validated.** `bake(User, email: 'bad')` returns the invalid record.
- **Attributes you never mention still get inferred values**, in every layer combination.

```ruby
FactoryBakery.define(Account) do
  skip :avatar_remote_url

  trait :with_avatar do
    avatar_remote_url { 'https://example.test/a.png' } # replaces the skip
  end
end

FactoryBakery.bake(Account)                           # setter not called
FactoryBakery.bake(Account, :with_avatar)             # trait value wins
FactoryBakery.bake(Account, avatar_remote_url: nil)   # explicit nil wins, setter runs
```

## Alias groups

An association, its foreign key columns and (for polymorphic ones) its type column form one **alias group**. The layer that mentions any member decides the whole group.

For `belongs_to :account`, the group is `account` and `account_id`. For `belongs_to :commentable, polymorphic: true`, it is `commentable`, `commentable_id`, `commentable_type`.

```ruby
FactoryBakery.define(User) do
  account { FactoryBakery.bake!(Account) }
end

FactoryBakery.bake(User, account_id: 7)          # the account block never runs
FactoryBakery.bake(User, account: existing)      # same
```

This also means:

- `skip :account` suppresses the association, `account_id`, and plugin auto-build.
- A trait that redeclares `account` replaces a base declaration of `account_id`.
- A plugin never sees one spelling of an edge alone. The `taken` list it receives is already expanded to the whole group.

Groups are read from the model's reflections at **bake time**, so definition files can load before the models.

## Guard columns are never filled

Heuristics never fill foreign keys, polymorphic type columns, the STI discriminator, the primary key or counter caches. An override, a declaration or the plugin can still set them. See [Heuristics](heuristics.md#what-is-never-filled).

## Overrides and fill_optional

`bake` and `bake!` treat `true`, `false`, an array, or `nil` for `fill_optional:` as a bake option. Any other value passes through as an attribute override for a model with an attribute named `fill_optional`.

```ruby
FactoryBakery.bake(User, fill_optional: true)
FactoryBakery.bake(User, fill_optional: [:bio, :website])
```

## Overrides on associations

Inside an `association` declaration, use `with:` for the child's overrides. See [Associations](associations.md#the-association-dsl).

```ruby
association :category, :featured, with: { name: 'News' }
```

Overrides placed beside the options raise an `ArgumentError`. The `with:` hash is passed to the child's bake as its call-site overrides, so it beats the child's declarations and traits.
