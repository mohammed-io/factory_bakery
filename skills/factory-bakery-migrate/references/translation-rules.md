# Translation rules: factory_bot to FactoryBakery

Translate one factory at a time into the **new** directory (`spec/bakery` or `test/bakery`). Never edit the old factory file. Translate 1:1 first. Simplification is a separate, user-approved step.

## File and header

```ruby
# before: spec/factories/posts.rb
FactoryBot.define do
  factory :post do
    # ...
  end
end
```

```ruby
# after: spec/bakery/post.rb
FactoryBakery.define(Post) do
  # ...
end
```

| factory_bot | FactoryBakery |
| --- | --- |
| `factory :post` (class `Post`) | `FactoryBakery.define(Post)` |
| `factory :admin, class: 'User'` | `FactoryBakery.define(:admin, klass: User)` |
| `factory :admin, class: User` | `FactoryBakery.define(:admin, klass: User)` |
| `factory :admin, class: 'Admin'` where `Admin < User` | Nothing: `bake!(Admin)` uses `User`'s definition. `define(Admin)` only when a test depends on a value that differs (it replaces the inherited definition, so repeat the lines it needs) |
| `factory :post` where call sites only use `create(:post)` | `define(Post)` and the call becomes `bake!(Post)` |
| One file, many factories | One definition per model, in one file per model |

Use a **class** key when the factory name equals the class (`:post` and `Post`). Use a **symbol with `klass:`** when it does not, or when tests create the same class under several names.

## Attributes

| factory_bot | FactoryBakery | Note |
| --- | --- | --- |
| `title { 'x' }` | `title { 'x' }` | Same |
| `title 'x'` | `title { 'x' }` | The static form raises: `Static attributes are unsupported; use title { "x" }` |
| `title { Faker::Lorem.sentence }` | `title { Faker::Lorem.sentence }` (1:1) | Droppable later: inference covers it. `Faker::` is not covered by the FactoryBakery seed |
| `created_at { 1.day.ago }` | `created_at { 1.day.ago }` | Keep if a test depends on it |
| `title { nil }` | `title { nil }` | Explicit `nil` is honored |
| `email { "#{name}@x.com" }` | Same block | Resolves the winning `name` (call-site override, trait, declaration or inference). A cycle (`a { b }`, `b { a }`) raises `Cyclic attribute dependency: a -> b -> a` |
| `skip_create`, `to_create { ... }` | **Blocker** | `bake!` always calls `save!`. A test that relies on the record not being saved (or saved another way) cannot be a rename. Dropping the line is not a translation |

## Sequences

```ruby
# before
sequence(:email) { |n| "user#{n}@example.com" }
```

```ruby
# after: a counter at the top of the file
counter = 0
FactoryBakery.define(User) do
  email { "user#{counter += 1}@example.com" }
end
```

If the column is `uniqueness`-validated and no test checks the shape, the 1:1 translation is the top-of-file counter above, or no line at all (inference regenerates a colliding value). Do not translate to `SecureRandom.hex`: it is not covered by the FactoryBakery seed, so `--seed N` no longer reproduces that value. The same goes for `rand` and `Faker::` calls in blocks (only FFaker inside the gem is seeded). Keep them 1:1 if you must, and know a replay needs them pinned ([diagnostics](../../factory-bakery-diagnostics/SKILL.md#1-reproduce)).

## Associations

| factory_bot | FactoryBakery |
| --- | --- |
| `association :author` | `association :author` (add the class when the name differs: `association :author, User`) |
| `association :author, factory: :user` | `association :author, User` |
| `association :author, factory: :admin` where `:admin` is registered | `association :author, factory: :admin` |
| `association :author, :admin` | `association :author, :admin`. Here `:admin` is a **trait on the target's definition** (`User`'s), so declare `trait :admin` there. It is not a factory name |
| `association :author, name: 'Ann'` | `association :author, with: { name: 'Ann' }` |
| `association :author, strategy: :create` | `association :author, persist: true` |
| `association :author, strategy: :build` | `association :author` |
| bare `author` (implicit association) | `association :author`, or nothing when the edge is required |
| `author { association :user }` | `association :author, User` |
| `author { create(:user) }` | `association :author, User, persist: true` |
| `author { build(:user) }` | `association :author, User` |
| `author { create(:user, name: 'Ann') }` | `association :author, User, persist: true, with: { name: 'Ann' }` |
| An association the DSL refuses (`has_many :through`, HABTM), a registry lookup, a cross-record rule, a Sequel model | `tags { [FactoryBakery.bake(Tag)] }`: a block that bakes |
| `comments { build_list(:comment, 3) }` | `association :comments, count: 3` |
| `after(:build) { \|p\| p.comments << build(:comment) }` | Not supported (callback) |
| polymorphic `commentable { association :post }` | `association :commentable, Post` |
| `post { nil }` | `post { nil }` |

Two cautions on the `author { ... }` rows:

- **A sibling reads it.** An explicit `association` runs **after** the attribute blocks, so `name { "#{author.name}'s post" }` cannot read it. When any sibling block reads `author`, keep it as an attribute block (`author { FactoryBakery.bake!(User) }`) rather than rewriting it to `association`. Unrewritten means more lines, not a different test ([definitions guide](../../../docs/guide/definitions.md)).
- **It was saved.** `author { create(:user) }` and `strategy: :create` saved the parent, and `author { build(:user) }` did not. Keep `persist: true` wherever the old factory saved the parent (those two, or `use_parent_strategy = false`, which made a `build` create its parents). Dropping it changes row counts and ids.

### Child blocks must pass the owner

```ruby
# before
comments { build_list(:comment, 2) }
```

```ruby
# after (a block, when the children need custom values)
association(:comments) { |post| Array.new(2) { |i| FactoryBakery.bake(Comment, post: post, body: "c#{i}") } }
```

`association :comments, count: 2` is the simple form.

## Traits

| factory_bot | FactoryBakery |
| --- | --- |
| `trait :admin do ... end` | `trait :admin do ... end` (same) |
| trait using another trait (`admin` inside a trait body) | Repeat the lines. A trait cannot call a trait |
| `factory :admin, parent: :user` (same class) | `define(:admin, klass: User)` repeating the parent's lines plus the child's, so the call stays a pure rename: `create(:admin)` becomes `bake!(:admin)`. Not a trait on the parent: that changes the call to `bake!(User, :admin)`, which is not a rename |
| `factory :admin, parent: :user, class: 'Admin'` with `Admin < User` | Nothing, if `User`'s definition already bakes an `Admin`: a class without a definition uses its nearest ancestor's, traits included. The call becomes `bake!(Admin)` |
| The same, and a test depends on a value that differs | `define(Admin)` with the lines it needs. It **replaces** the inherited definition (no merge), so repeat the parent's lines it still needs and its traits |
| `parent:` across unrelated classes | A second definition with the parent's lines repeated. Only ancestor classes are searched |
| `traits_for_enum :status` | A trait per state a test uses, or none (enum inference) |
| `trait :x` with `transient` | See transients |

## Transients and callbacks

| factory_bot | FactoryBakery |
| --- | --- |
| `transient do foo { 1 } end` used only to compute attributes | A local inside `define`: `foo = 1`. Or declare it and read it from a sibling block |
| `transient` passed at the call site | Not supported. Blocker |
| `after(:build)`, `after(:create)`, `before(:create)`, `callback` | Report definition callbacks. Keep existing call-site blocks on `bake` or `bake!` |
| `initialize_with { new(a: 1) }` | `initialize_with(a: 1)` |
| `initialize_with { new(a: name) }` | Blocker (a block, and it reads a sibling) |

## Call sites (renames only)

Only the factory call changes. Arguments after the name carry over unchanged.

| Before | After |
| --- | --- |
| `create(:post)` | `FactoryBakery.bake!(Post)` |
| `create(:post, title: 'x')` | `FactoryBakery.bake!(Post, title: 'x')` |
| `create(:post, :published, title: 'x')` | `FactoryBakery.bake!(Post, :published, title: 'x')` |
| `build(:post)` | `FactoryBakery.bake(Post)` |
| `create(:admin)` (symbol factory) | `FactoryBakery.bake!(:admin)` |
| `FactoryBot.create(:post)` | `FactoryBakery.bake!(Post)` |
| `create_list(:post, 3)` | `Array.new(3) { FactoryBakery.bake!(Post) }` |
| `create_list(:post, 3, :published, title: 'x')` | `Array.new(3) { FactoryBakery.bake!(Post, :published, title: 'x') }` |
| `build_list(:post, 2)` | `Array.new(2) { FactoryBakery.bake(Post) }` |
| `create_pair(:post)` | `Array.new(2) { FactoryBakery.bake!(Post) }` |
| `attributes_for(:post)` | `bakery_attributes_for(Post)` through a helper (see below) |
| `build_stubbed(:post)` | Blocker |
| `create(:post) { \|p\| ... }` | `FactoryBakery.bake!(Post) { \|p\| ... }` (yields after the save is verified and the transaction or savepoint finished) |
| `build(:post) { \|p\| ... }` | `FactoryBakery.bake(Post) { \|p\| ... }` (yields after the build) |

Which spelling for the name? A symbol name maps to the class (`:post` to `Post`). If the factory was registered under a different name than the class, keep the symbol (`bake!(:admin)`) and register it with `klass:`.

### The helper for `attributes_for`

Only when tests use it. A new file, so the test diff stays renames. Give it a **distinct name**, so it never shadows factory_bot's `attributes_for` while both libraries coexist.

```ruby
# spec/support/bakery_helpers.rb
module BakeryHelpers
  def bakery_attributes_for(klass, *traits, **overrides)
    FactoryBakery.bake(klass, *traits, **overrides)
      .attributes.except('id', 'created_at', 'updated_at').compact.symbolize_keys
  end
end

RSpec.configure { |config| config.include BakeryHelpers }
```

(If you must keep the name `attributes_for`, start the method with `return super unless klass.is_a?(Class)`, so factory_bot's symbol form still reaches factory_bot. The distinct name is simpler and safer.)

Before relying on it:

1. **Confirm `spec/support` is loaded.** Rails' generated `rails_helper.rb` can ship the `spec/support/**/*.rb` require commented out. If it is, the helper is never included. Requiring it from a file the suite already loads is a change outside renames: ask, or report it.
2. **Match factory_bot's output.** `attributes_for` returns **symbol** keys, only the attributes the factory declares, and keeps an explicit `nil`. The helper returns symbol keys, but it also lists every non-nil column the gem filled and drops `nil`s. If a test compares the whole hash, the key set, or an explicit `nil`, the helper does not match: it is a **blocker**. Do not edit the test to fit.

## Putting a definition to bed

After translating, the 1:1 definition for a model is correct but verbose. Do the whole 1:1 migration and verify it green first (Phase 6). Only then **ask the user** whether to simplify (Phase 7), and re-run that model's tests and doctor under `FACTORY_BAKERY_SEED=1,2,3` after each dropped line. Keep every named definition, even an empty one. Keep a line only when:

1. A test depends on that exact value, or
2. The model cannot bake without it. Say which: custom validator, registry, format, side effect, cross-record rule, cycle, view.

## Worked example

Before:

```ruby
FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    name { Faker::Name.name }
    password { 'secret123' }
    role { 'member' }
    association :account

    trait :admin do
      role { 'admin' }
    end
  end
end
```

1:1 translation:

```ruby
counter = 0
FactoryBakery.define(User) do
  email { "user#{counter += 1}@example.com" }
  name { Faker::Name.name }
  password { 'secret123' }
  role { 'member' }
  association :account

  trait :admin do
    role { 'admin' }
  end
end
```

After the user agrees to reduce, assuming `email` has `uniqueness` (no test checks its shape), `name` is NOT NULL, `password` uses `has_secure_password`, `role` is an `inclusion` with default `'member'`, `account` is a required `belongs_to`, and a test asserts `user.admin?` through `:admin`:

```ruby
FactoryBakery.define(User) do
  trait :admin do
    role { 'admin' }   # a test asserts on this state
  end
end
```
