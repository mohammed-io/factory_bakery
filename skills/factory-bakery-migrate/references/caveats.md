# Caveats and edge cases

Every one of these has bitten a real migration or a real-app bake (Mastodon, Discourse). Read the ones that match what the inventory found. Cross-references: [capability matrix](capability-matrix.md), the [diagnostics catalog](../../factory-bakery-diagnostics/references/diagnostics.md).

The standing rule for every caveat: **do not fix a caveat by editing a test.** Fix it in a definition or a helper, or report a blocker.

## Compatibility with the existing suite

| Caveat | What happens | What to do |
| --- | --- | --- |
| **Random values vs fixed ones** | factory_bot with Faker is random too, but a test may rely on a value's shape (`'Ada'`, a sequence `user1@`) | Keep the line when a test asserts or looks up by the value. Run the suite twice with different seeds to catch hidden dependence |
| **Hidden dependence on an optional association** | A factory had `association :author` for an **optional** `belongs_to`, and a test reads `post.author`. After simplifying, `author` is `nil` in `:required_only` | The verification run catches it. Restore the line (`association :author`), and say "a test depends on this" |
| **Row counts** | `expect { create(:post) }.to change(User, :count)`. The plugin builds required parents, and `:all` builds more | Compare counts in the verification run. Use `:required_only` (default). Keep an `association` line if a test counts a row |
| **Faker vs FFaker** | Locale-sensitive assertions on Faker values | Keep the line |
| **`FactoryBot.use_parent_strategy = false`** | `build` created parents. `bake` leaves parents unsaved | `association :x, persist: true` on the edges tests expect saved |
| **Callbacks that depend on `create` vs `build`** | `after_create`/`after_commit` timing is the same for `bake!` as `create` (it calls `save!`). `bake` never saves | A rename of `build` to `bake` is exact. Check any `after_commit` reliance |
| **Ordering** | `let!` order and definition order | Definitions are independent files. Order inside a definition is declaration order |
| **Tests that call `attributes_for`** | No built-in | Helper, or blocker |

## Associations

### A custom validator reads a parent's id: `persist: true`

An unsaved parent has `id == nil`. `user_id == invited_by_id` is `nil == nil`. Use `association :user, persist: true`. If two edges target the same class, persist both, or the second unsaved sibling triggers `IncompletePersistenceError` ([sibling case](../../factory-bakery-diagnostics/references/diagnostics.md#nested-bake-sibling-of-same-class)).

```ruby
# factory_bot: association :user, strategy: :create
association :user, persist: true
```

### Reuse picks the owner's own parent: `strategy: :fresh`

`strategy: :reuse_non_unique` takes the oldest matching row. A custom validator ("cannot vote on your own poll") may forbid that row. The gem sees unique **indexes** and uniqueness **validators**, not custom rules. Use `strategy: :fresh` on that edge. Real case: Mastodon `PollVote`.

### Uniqueness of literal overrides on children

`association :items, count: 2, with: { label: 'same' }` gives both children the same literal. If it is uniqueness-validated, the owner is invalid. factory_bot's sequence would have varied it. Leave the value to inference, or build the collection in a block with distinct values.

### Cycles

A required cycle raises `CyclicAssociationError`. In factory_bot an `association` pointing back at itself used to be broken by `build` strategies. Declare one side: `parent { nil }`, or `skip :parent`. A declared child block that bakes its own required parent also cycles: pass the owner (`FactoryBakery.bake(Article, cat: cat)`).

### `has_one` created by a callback

An `after_create :create_profile` plus a factory-declared profile double-inserts. For gem-built children the gem keeps the callback's row. For a child you declare, remove the declaration, or `skip` it. Real case: Discourse `User` and `user_stats`.

### Polymorphic

Discovered from an `inclusion` list on the type column, or loaded `as:` inverses. Else declare `association :commentable, Post`. A factory with `commentable { association(:post) }` becomes `association :commentable, Post`. `Rails.application.eager_load!` runs once if needed: set `eager_load: false` in suites that manage loading.

### STI

The `type` column is never filled. `create(:admin)` where `Admin < User` becomes `FactoryBakery.bake!(Admin)`. An abstract base needs a concrete subclass: `initialize_with(type: 'Sub')` or `define(:x, klass: Sub)`. Real case: Discourse `Chat::Channel`.

### Read-only views and null objects

`bake` populates a view-backed model. `bake!` raises `ReadOnlyTargetError`. As a parent: `skip :instance` and set the natural key (Mastodon `InstanceModerationNote`). A null object that can never be saved (Discourse `Chat::NullMessage`) is not bakeable: exclude it. A factory that built such an object with `build` becomes `bake`. One that saved it cannot become `bake!`: report it as a blocker.

### Optional edges and `:all`

`:all` builds optional edges, and an invalid optional child is silently dropped. Most suites stay on `:required_only`. A factory that created optional records on purpose keeps an `association` line.

## Values and validators

### Sequences

No `sequence` DSL. Options:

| Need | Use |
| --- | --- |
| Distinct values only | Delete the sequence. A uniqueness-validated column is regenerated on collision |
| A readable counter (`user1@x.com`) a test checks | `counter = 0` at the top of the definition file, then `email { "user#{counter += 1}@x.com" }` |
| Global `generate(:email)` | A helper with a counter. Else blocker |

The counter resets when the file is reloaded. It is not thread-safe.

### Transients

A transient used only to compute another attribute becomes a local inside `define`. A transient passed at the call site (`create(:user, posts_count: 3)`) has no equivalent: blocker.

```ruby
FactoryBakery.define(Account) do
  owner = nil
  user { owner = FactoryBakery.bake!(User) }
  name { "#{owner.name}'s account" }   # works only while `user` is not overridden
end
```

If a test overrides `user:`, the `user` block does not run and `owner` stays `nil`. That is a blocker for that factory.

### Callbacks

`after(:build)`, `after(:create)`, `before(:create)` have no equivalent. Pre-save record preparation can be a block. Post-save work cannot. Report the file and line.

### JSON and YAML in text columns

A text column cast to JSON by an index gets a JSON string. Any other structured text (YAML, JSON with a required shape) needs a block (Discourse `FormTemplate`: `template { [...].to_yaml }`).

### Provider and registry inclusion lists

Values that come from a registry, a provider class list or a site setting are not discoverable. A block returns one (Discourse `AdminDashboardReport`: `source { 'core_report' }`). Enum and `inclusion:` lists declared on the model are automatic.

### Enum and inclusion domains

Automatic. When a custom validator **also** restricts the domain (Mastodon `Follow#languages`), write a block.

### Regex formats

Generated from the regex. Two mutually constraining regexes, or an exotic one, may exhaust: a literal wins (Mastodon `Account#username`). See [format-exhaustion](../../factory-bakery-diagnostics/references/diagnostics.md#format-exhaustion).

### Time-relative validations

`comparison:` and `numericality:` bounds are handled. A **custom** time rule ("expires within 5 minutes to 1 month") needs a block (`expires_at { 1.day.from_now }`).

### DB-only constraints

Check constraints, composite unique indexes and triggers are invisible. A block gives an accepted value. A `NOT NULL` foreign key is built by the plugin in `:required_only`.

### Side-effecting setters

`*_remote_url` writers are never filled. Other setters that fetch or enqueue need `skip` (Mastodon `Account`).

## Definitions

| Caveat | Detail |
| --- | --- |
| **No static shorthand** | `name 'Ada'` assigns nothing and suppresses inference. Rewrite to `name { 'Ada' }` |
| **Blocks cannot read siblings** | No evaluator. Use locals in `define` |
| **Declarations may run twice** | The verified fallback can rebuild. Blocks with non-database side effects can repeat |
| **A typo in an attribute name is silent** | Values go through setters. A missing setter is skipped |
| **Definitions are global** | No per-example factory change. Use call-site overrides |
| **Class-keyed definitions go stale on reload** | Tests do not reload. Symbol factories re-resolve |
| **`define` replaces silently** | A second `define(User)` replaces the first. Two files defining the same model: the last loaded wins (sorted path order) |
| **`bake!` ignores a block** | `create(:x) { |x| ... }` cannot be renamed |

## Environment

| Caveat | Detail |
| --- | --- |
| **Both gems load `spec/factories`** | Use `spec/bakery` plus `definition_paths` |
| **Plugins vanish after `reset_plugins!`** | Do not call it in an app suite |
| **`doctor` writes rows (rolled back)** | Test environment only |
| **Gem in the wrong group** | Definitions load at boot wherever the gem loads |
| **Ruby < 3.2, Rails < 7.1** | Not supported |
