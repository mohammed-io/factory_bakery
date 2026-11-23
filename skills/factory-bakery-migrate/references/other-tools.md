# Other tools: fabrication, machinist, fixtures, `create!` helpers

The same ground rules apply to all of them: isolate in a worktree, suite identical to baseline, test files change only by renaming the data-creation call, two-way doors first, ask before simplifying, and **never delete the old definitions automatically** (see [doors.md](doors.md)).

The FactoryBakery side of every table below is verified against this gem. The Fabrication and Machinist side is written from those tools' documented behavior and was **not** run here: confirm each mapping against the version the project uses (`Gemfile.lock`) and by running the suite.

## Fabrication

| Fabrication | FactoryBakery |
| --- | --- |
| `Fabricator(:user) { name 'Ada' }` | `FactoryBakery.define(User) { name { 'Ada' } }` (note the block) |
| `Fabricator(:admin, from: :user) { ... }` (same class) | `define(:admin, klass: User)` repeating the parent's lines, so `Fabricate(:admin)` stays a rename (`bake!(:admin)`). A trait on `User` would change the call |
| `Fabricator(:admin, from: :user, class_name: 'Admin')` with `Admin < User` | Empty child body: nothing (inherits). Otherwise in the 1:1 step: `define(Admin)` with the parent's lines plus the child's. Falling back to inheritance is a Phase 7 drop |
| `Fabricator(:user, class_name: 'Ns::User')` | `define(:user, klass: Ns::User)` |
| `Fabricate(:user)` | `FactoryBakery.bake!(User)` |
| `Fabricate(:user, name: 'x')` | `FactoryBakery.bake!(User, name: 'x')` |
| `Fabricate.build(:user)` | `FactoryBakery.bake(User)` |
| `Fabricate.times(3, :user)` | `Array.new(3) { FactoryBakery.bake!(User) }` |
| `Fabricate.attributes_for(:user)` | `bakery_attributes_for(User)` through a helper, a blocker if it cannot match (see [translation-rules](translation-rules.md#the-helper-for-attributes_for)) |
| `Fabricate(:user) { name 'x' }` (block form) | Blocker (the block form changes the call) |
| `after_build`, `after_create`, `before_validation` hooks | Not supported |
| `transient` | Locals inside `define`, or blocker if passed at the call site |
| `association`-style nested `Fabricate` | `association :x` |

Before:

```ruby
Fabricator(:post) do
  title { Faker::Lorem.sentence }
  author
end
```

After (1:1, then simplified):

```ruby
FactoryBakery.define(Post) do
  title { Faker::Lorem.sentence }
  association :author, User
end
# simplified: no definition. `title` and a required `author` are inferred.
```

## Machinist

| Machinist | FactoryBakery |
| --- | --- |
| `User.blueprint { name { 'Ada' } }` | `FactoryBakery.define(User) { name { 'Ada' } }` |
| `User.blueprint(:admin) { role { 'admin' } }` | `trait :admin do role { 'admin' } end` |
| `User.make` (Machinist 1 saves) | `FactoryBakery.bake!(User)` |
| `User.make` (Machinist 2 builds) | `FactoryBakery.bake(User)` |
| `User.make!` | `FactoryBakery.bake!(User)` |
| `User.make(:admin, name: 'x')` | `FactoryBakery.bake!(User, :admin, name: 'x')` |
| `User.plan` | A helper, or blocker |
| `sn` (serial number) | A counter local at the top of the definition file |
| `object` inside a blueprint | `association :x` |

Check the Machinist version first: `make` saves in Machinist 1 and only builds in 2. A wrong choice changes behavior, so confirm with a test run.

## Rails fixtures

Fixtures are shared, named data loaded once for the whole suite. FactoryBakery builds data per example. There is no direct rename (`users(:ada)` has no equivalent), so a conversion would change tests. That violates the renames-only rule.

Therefore:

1. **Do not convert fixtures automatically.**
2. Report them in the inventory: how many fixture files, how many `fixture_name(:label)` call sites.
3. If the user asks to convert a specific fixture anyway, treat it as a **separate, one-way-door task** (see [doors.md](doors.md)): one fixture file at a time, replacing each `users(:ada)` with a `let` that bakes with the fixture's distinguishing values. This changes tests and needs the user's explicit approval for those changes.
4. Never delete the fixture files without the same final keep/delete question.

New tests can use FactoryBakery next to existing fixtures. The two coexist, because fixtures load from `test/fixtures` or `spec/fixtures`, which FactoryBakery never reads.

## Hand-rolled `create!` helpers

```ruby
# before
def create_user(attrs = {})
  User.create!({ name: 'Ada', email: "u#{rand(99_999)}@example.com" }.merge(attrs))
end
```

Replace the **body**, keep the **name and signature**, so call sites do not change:

```ruby
# after
def create_user(attrs = {})
  FactoryBakery.bake!(User, **attrs)
end
```

`bake!` also accepts a block that yields the saved record, so a helper that did `User.create!(attrs).tap { ... }` keeps its shape. Values the helper set that a test asserts on go into a definition:

```ruby
FactoryBakery.define(User) do
  name { 'Ada' }   # tests assert on this
end
```

Other shapes:

| Helper | Replacement |
| --- | --- |
| `Model.create!(attrs)` inline in a test | `FactoryBakery.bake!(Model, **attrs)` (a rename of the creation call) |
| `Model.new(attrs)` inline | `FactoryBakery.bake(Model, **attrs)` |
| `Model.create!(...)` with a block | Blocker |
| A helper that creates several related records | Keep its body. Replace each `create!` inside. If it relies on a specific graph, add `association` lines |
| Seeds and rake tasks | Out of scope. Report |

String keys in `attrs` are fine. A helper that mixes association objects with scalars passes them through as overrides.

## Mixed repositories

A repository can have several of these at once. Migrate **one tool at a time**, each in its own set of commits, each ending with the suite equal to the baseline. Ask the keep/delete question once per tool at the end, or once for all, as the user prefers.
