# Caveats and edge cases

Every one of these has bitten a real migration or a real-app bake (Mastodon, Discourse). Read the ones that match what the inventory found. Cross-references: [capability matrix](capability-matrix.md), the [diagnostics catalog](../../factory-bakery-diagnostics/references/diagnostics.md).

The standing rule for every caveat: **do not fix a caveat by editing a test.** Fix it in a definition or a helper, or report a blocker.

## Compatibility with the existing suite

| Caveat | What happens | What to do |
| --- | --- | --- |
| **Random values vs fixed ones** | factory_bot with Faker is random too, but a test may rely on a value's shape (`'Ada'`, a sequence `user1@`) | Keep the line when a test asserts or looks up by the value. Run the suite twice with different seeds (`rspec --seed A`, `--seed B`, with `factory_bakery/rspec` required) to catch hidden dependence. A failure replays with its seed |
| **Hidden dependence on an optional association** | A factory had `association :author` for an **optional** `belongs_to`, and a test reads `post.author`. After simplifying, `author` is `nil` in `:required_only` | The verification run catches it. Restore the line (`association :author`), and say "a test depends on this" |
| **Row counts** | `expect { create(:post) }.to change(User, :count)`. The plugin builds required parents, and `:all` builds more | Compare counts in the verification run. Use `:required_only` (default). Keep an `association` line if a test counts a row |
| **Faker vs FFaker** | Locale-sensitive assertions on Faker values | Keep the line |
| **`FactoryBot.use_parent_strategy = false`** | `build` created parents. `bake` leaves parents unsaved | `association :x, persist: true` on the edges tests expect saved |
| **Callbacks that depend on `create` vs `build`** | `after_create`/`after_commit` timing is the same for `bake!` as `create` (it calls `save!`). `bake` never saves | A rename of `build` to `bake` is exact. Check any `after_commit` reliance |
| **Ordering** | `let!` order and definition order | Winning declarations run in order unless a sibling read resolves a later declaration first |
| **Tests that call `attributes_for`** | No built-in | Helper, or blocker |

## Associations

### A custom validator reads a parent's id: `persist: true`

An unsaved parent has `id == nil`. `user_id == invited_by_id` is `nil == nil`. Use `association :user, persist: true` on the edge whose id the validator reads. Two edges to the same class work with different options: a nested `bake!` checks records by build lineage, so the other edge may stay unsaved under plain `bake`, and an enclosing `bake!` verifies both ([sibling case](../../factory-bakery-diagnostics/references/diagnostics.md#nested-bake-sibling-of-same-class); the unreleased fix in `CHANGELOG.md`, so a gem that predates it raises `IncompletePersistenceError` here).

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

The `type` column is never filled. `create(:admin)` where `Admin < User` becomes `FactoryBakery.bake!(Admin)`, and `Admin` uses `User`'s definition when it has none of its own (nearest ancestor class, traits included, never `Object`). Give `Admin` its own definition only when it must differ: it replaces the inherited one, so repeat the lines it still needs. An abstract base needs a concrete subclass: `initialize_with(type: 'Sub')` or `define(:x, klass: Sub)`. Real case: Discourse `Chat::Channel`. A custom validator that rejects the drawn `type` is not searched around: declare it ([ADR-0008](../../../docs/adr/0008-user-chooses-domain-values.md)).

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
  user { FactoryBakery.bake!(User) }
  name { "#{user.name}'s account" }   # reads the winning `user`, including a call-site override
end
```

A block can read a sibling attribute, so the value follows overrides and traits (a cycle raises `Cyclic attribute dependency: a -> b -> a`). Do not copy the old trick of capturing the record in a local from inside another block: if a test overrides `user:`, that block never runs and the local stays `nil`. Plain `foo = 1` locals inside `define` stay fine for constants.

### Callbacks

`after(:build)`, `after(:create)`, and `before(:create)` have no definition-level equivalent. Report the file and line if a hook must run for every call. An existing call-site block can stay on `bake` or `bake!`. The latter yields after its transaction or savepoint finishes.

### JSON and YAML in text columns

A text column cast to JSON by an index gets a JSON string. Any other structured text (YAML, JSON with a required shape) needs a block (Discourse `FormTemplate`: `template { [...].to_yaml }`).

### Provider and registry inclusion lists

Values that come from a registry, a provider class list or a site setting are not discoverable. A block returns one (Discourse `AdminDashboardReport`: `source { 'core_report' }`). Enum and `inclusion:` lists declared on the model are automatic.

### Enum and inclusion domains

Automatic. When a custom validator **also** restricts the domain (Mastodon `Follow#languages`), write a block: the gem does not try other enum members, booleans or STI types until one passes, because the choice is a domain decision ([ADR-0008](../../../docs/adr/0008-user-chooses-domain-values.md)). Keep a factory_bot line that set such a value when reducing.

### Regex formats

Generated from the regex. Two mutually constraining regexes, or an exotic one, may exhaust: a literal wins (Mastodon `Account#username`). See [format-exhaustion](../../factory-bakery-diagnostics/references/diagnostics.md#format-exhaustion).

### Time-relative validations

`comparison:` and `numericality:` bounds are handled. A **custom** time rule ("expires within 5 minutes to 1 month") needs a block (`expires_at { 1.day.from_now }`).

### DB-only constraints

Check constraints, composite unique indexes and triggers are invisible. A block gives an accepted value. A `NOT NULL` foreign key is built by the plugin in `:required_only`.

### Side-effecting setters

`*_remote_url` writers are left blank automatically, with one WARN per model and attribute (`left Account#avatar_remote_url blank on purpose`). Nothing to write unless a test needs a value: then set it in a definition or an override. Other setters that fetch or enqueue need `skip`, or a definition returning a safe value.

## Definitions

| Caveat | Detail |
| --- | --- |
| **Static declarations raise** | Rewrite `name 'Ada'` to `name { 'Ada' }` |
| **Sibling reads** | Keep `label { "#{name}-x" }`. Overrides and traits change the value it sees. Reads honor `fill_optional` and `skip` |
| **Declarations may run twice** | The verified fallback can rebuild. Blocks with non-database side effects can repeat |
| **A typo in an attribute name is silent** | Values go through setters. A missing setter is skipped |
| **Definitions are global** | No per-example factory change. Use call-site overrides |
| **Class-keyed definitions go stale on reload** | Tests do not reload. Symbol factories re-resolve |
| **Class and symbol keys are separate** | `define(:post, klass: Post)` is reached only by `bake(:post)`. `bake(Post)` does not see it |
| **A subclass definition replaces the inherited one** | A class with no definition uses its nearest ancestor's. An exact definition does not merge with it |
| **File-level locals are shared across bakes** | Fine for a counter. Never cache a record in one |
| **`define` replaces silently** | A second `define(User)` replaces the first. Two files defining the same model: the last loaded wins (sorted path order) |
| **Call-site blocks** | Keep the block on `bake!`. It runs after the save is verified and the transaction or savepoint finishes |

## Environment

| Caveat | Detail |
| --- | --- |
| **Both gems load `spec/factories`** | Use `spec/bakery` plus `definition_paths` |
| **Plugins vanish after `reset_plugins!`** | Do not call it in an app suite |
| **`doctor` writes rows (rolled back)** | Test environment only |
| **Gem in the wrong group** | Definitions load at boot wherever the gem loads |
| **Ruby < 3.2, Rails < 7.1** | Not supported |
