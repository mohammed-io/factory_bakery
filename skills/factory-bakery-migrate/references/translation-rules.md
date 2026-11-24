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
| `factory :admin, class: 'Admin'` where `Admin < User` (no `parent:`, not nested) | Register an exact `define(Admin)` with the factory's own lines — even when the body is empty (`define(Admin) {}`), because a bare `class:` inherits no factory_bot factory and the empty exact definition shadows the unintended ancestor definition. Keep the exact definition in Phase 7 while `define(User)` keeps a line: without it `bake!(Admin)` inherits lines `create(:admin)` never had. Remove it in Phase 7 only when the effective ancestor's reduced definition reproduces it for every used call; an empty ancestor alone is not enough |
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
| `attr { \|rec\| ... }` (attribute block with a parameter) | Read siblings bare: `attr { sibling }`, or move the logic out of the block | factory_bot passes the record to attribute blocks that declare a parameter (`instance_exec(self, &block)`); FactoryBakery calls declaration blocks with **no** argument, so the parameter is `nil` and calling a method on it raises `NoMethodError: undefined method '...' for nil`. Read the sibling by bare name instead |
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

If the column is `uniqueness`-validated and no test checks the shape, the 1:1 translation is the counter above. Dropping the line is a Phase 7 decision (inference regenerates a colliding value). Do not translate to `SecureRandom.hex`: it is not covered by the FactoryBakery seed, so `--seed N` no longer reproduces that value. The same goes for `rand` and `Faker::` calls in blocks (FFaker is seeded during a bake, including in your blocks; `Faker::`, `rand` and `SecureRandom` are not). Keep them 1:1 if you must, and know a replay needs them pinned ([diagnostics](../../factory-bakery-diagnostics/SKILL.md#1-reproduce)).

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
| bare `author` (implicit association) | `association :author`, or nothing when the edge is required — but see the factory-name caution below |
| `author { association :user }` | `association :author, User` |
| `author { create(:user) }` | `association :author, User, persist: true` |
| `author { build(:user) }` | `association :author, User` |
| `author { create(:user, name: 'Ann') }` | `association :author, User, persist: true, with: { name: 'Ann' }` |
| An association the DSL refuses (`has_many :through`, HABTM), a registry lookup, a cross-record rule, a Sequel model | `tags { [FactoryBakery.bake(Tag)] }`: a block that bakes |
| `comments { build_list(:comment, 3) }` | `association :comments, count: 3` |
| `after(:build) { \|p\| p.comments << build(:comment) }` | Not supported (callback) |
| polymorphic `commentable { association :post }` | `association :commentable, Post` |
| `post { nil }` | `post { nil }` |

**Check the save timing of every edge.** For each migrated `association` line and each call strategy that uses it: factory_bot's default `create` saves a declared parent during owner construction. Use `persist: true` only when all relevant calls need an already-saved parent **and** the association phase runs early enough for them; when a sibling read, an owner setter or another declaration observes the saved parent earlier (an attribute block in declaration order), keep an ordered attribute block or a helper instead. Where `build` and `create` need different timing, a preserving helper is required — or report a blocker.

Two cautions on the `author { ... }` rows, plus one on the edge's name:

- **The edge resolves by class, not by factory name.** In factory_bot, `association :author` and a bare `author` build the factory named `:author`. In FactoryBakery the target is the association's **class** (the reflection's), and the definition used is that class's own or nearest-ancestor definition. So whenever a factory named `:x` exists and was **not** translated as the class-keyed definition holding the same lines (for example it became `define(:x, klass: OtherClass)`), translate to `association :x, factory: :x` — `factory:` resolves the registered symbol factory (`BakeryBuilder.resolve`), so the named definition's lines are used. Check every `bake!(X)` call site that relied on the same factory name the same way.
- **A sibling reads it.** With an explicit `association`, a sibling block that reads it gets nil and the edge is then not built at all (the record can end up invalid), so `name { "#{author.name}'s post" }` breaks. Keep the attribute block when any sibling reads `author`, with the old verb preserved: `author { create(:user) }` stays `author { FactoryBakery.bake!(User) }`, `author { build(:user) }` stays `author { FactoryBakery.bake(User) }`. Unrewritten means more lines, not a different test ([definitions guide](../../../docs/guide/definitions.md)). A factory the tests use as both `build` and `create`, with timing-sensitive associations, is a blocker unless a helper preserves both.
- **It was saved.** `author { create(:user) }` and `strategy: :create` saved the parent, and `author { build(:user) }` did not. Keep `persist: true` wherever the old factory saved the parent (those two, or `use_parent_strategy = false`, which made a `build` create its parents). Dropping it changes row counts and ids. The save-timing check above applies to this bullet too: persist early enough for every reader, or keep an ordered attribute block or helper.

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
| `factory :admin, parent: :user` (same class) | `define(:admin, klass: User)` repeating the parent's lines **and traits** plus the child's, so the call stays a pure rename: `create(:admin)` becomes `bake!(:admin)`. Not a trait on the parent: that changes the call to `bake!(User, :admin)`, which is not a rename |
| `factory :admin, parent: :user, class: 'Admin'` with `Admin < User` | The factory inherits :user's attributes. An empty body may translate to nothing: `bake!(Admin)` uses `define(User)`, but only when the effective ancestor definition already reproduces the selected parent's declarations, traits and defaults for every used call (a different named parent or a factory-level trait means register an exact subclass definition instead). With a body, in the 1:1 step: `define(Admin)` with the parent's lines plus the child's. Falling back to inheritance is a Phase 7 drop |
| The same, and a test depends on a value that differs | In the 1:1 step: `define(Admin)` with the parent's lines plus the child's. It **replaces** the inherited definition (no merge). Falling back to inheritance is a Phase 7 drop |
| `parent:` across unrelated classes | A second definition with the parent's lines repeated. Only ancestor classes are searched |
| `traits_for_enum :status` | A trait per state a test uses, or none (enum inference) |
| `trait :x` with `transient` | See transients |

## Transients and callbacks

| factory_bot | FactoryBakery |
| --- | --- |
| `transient do foo { 1 } end` used only to compute attributes | A local: `foo = 1` in the `define` body if it is a constant, inside the value block if it is computed or random (the `define` body runs once, ADR-0009). Or declare it and read it from a sibling block |
| `transient` passed at the call site | Not supported. Blocker |
| `after(:build)`, `after(:create)`, `before(:create)`, `callback` | Report definition callbacks. Keep existing call-site blocks on `bake` or `bake!` |
| `initialize_with { new(a: 1) }` | `initialize_with(a: 1)` |
| `initialize_with { new(a: name) }` | Blocker. `initialize_with` takes a Hash before the record is instantiated. Sibling reads are supported in attribute value blocks. |

## Call sites (renames only)

Only the factory call changes. Arguments after the name carry over unchanged.

| Before | After |
| --- | --- |
| `create(:post)` | `FactoryBakery.bake!(Post)` |
| `create(:post, title: 'x')` | `FactoryBakery.bake!(Post, title: 'x')` |
| `create(:post, :published, title: 'x')` | `FactoryBakery.bake!(Post, :published, title: 'x')` |
| `create(:user, :admin, name: 'x')` | `FactoryBakery.bake!(User, :admin, name: 'x')` |
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

For new code, the optional recipe equivalents are `FactoryBakery.recipe(User, :admin).bake!(name: 'x')` for `create` and `FactoryBakery.recipe(Post).bake` for `build`. Use the plain renames in the table by default for migrated tests so only the factory calls change.

### Call-site argument rules

Arguments do not all carry over blindly. `check_renames.rb` marks each of these REVIEW; treat them as a blocker unless the equivalence is provable:

- **`fill_optional:` is a FactoryBakery option**, not an attribute: `FactoryBakery.bake(target, *traits, fill_optional: nil, **overrides)` consumes it. A factory_bot call that passed `fill_optional:` as a (transient) override is silently swallowed by the option after the rename — translate it explicitly (a transient passed at the call site is a blocker anyway).
- **Positional, non-keyword arguments** (`create(:post, attrs)`, a bare hash, a splat): a trailing Hash is factory_bot attributes, and FactoryBakery may read a non-trait positional as a trait. REVIEW unless provably equivalent.
- **`create_list` overrides are evaluated once per list call in factory_bot; the `Array.new(n) { ... }` rewrite evaluates them once per item.** A counter in an override gives `[1, 1]` from factory_bot and `[1, 2]` from the rewrite. Anything but provably identical values for every item: REVIEW or blocker.
- **Abstract STI base** (`self.abstract_class = true`): bake the concrete subclass directly (`bake!(Chat::Channel)`); do not reach for `initialize_with(type: ...)` — instantiating the abstract base raises `NotImplementedError` (see the [diagnostics catalog](../../factory-bakery-diagnostics/references/diagnostics.md#silent-failures)).

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

Minitest: include it where `FactoryBakery::Methods` is included — `class ActiveSupport::TestCase; include BakeryHelpers; end` in `test/test_helper.rb`, or `include BakeryHelpers` in the test class.

(If you must keep the name `attributes_for`, start the method with `return super unless klass.is_a?(Class)`, so factory_bot's symbol form still reaches factory_bot. The distinct name is simpler and safer.)

Before relying on it:

1. **Confirm `spec/support` is loaded.** Rails' generated `rails_helper.rb` can ship the `spec/support/**/*.rb` require commented out. If it is, the helper is never included. Requiring it from a file the suite already loads is a change outside renames: ask, or report it.
2. **Match factory_bot's output.** The contract: the returned hash must equal factory_bot's for the call — the factory's eligible declarations plus the eligible call-site overrides, symbol keys, explicit `nil` kept. Compare the exact keys and the value semantics for each used target and trait combination; any difference marks the call **blocked**: report it. Do not edit the test to fit. The `.attributes.compact` helper above is only a candidate: it qualifies for a factory with no associations, no `nil` declarations and no extra inferred keys — `.attributes` includes ActiveRecord-declared attributes (`attribute :x, :string`) and defaults, and can omit plain accessors, so the exact key and value comparison decides — and only after it passes that comparison.

## Putting a definition to bed

After translating, the 1:1 definition for a model is correct but verbose. Do the whole 1:1 migration and verify it green first (Phase 6). Only then **ask the user** whether to simplify (Phase 7), and re-run that model's tests and doctor under `FACTORY_BAKERY_SEED=1,2,3` after each dropped line. A named definition never merges with the class-keyed one. Apply the keep rules per target and trait: it repeats a class line only when the original named factory had it (inherited via `parent:`/nested) or the model cannot bake without it — never copy a regular factory's retained line into an independent named factory (probed: the copy turns a nil name into the class-keyed definition's kept value). Keep a line only when:

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
