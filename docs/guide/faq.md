# FAQ

Short answers. Each links to the page with the detail. For a specific error message, search [diagnostics.md](../../skills/factory-bakery-diagnostics/references/diagnostics.md).

## Basics

**Why is an optional column `nil`?**
A default bake fills only what a valid record needs. Use `fill_optional: true` or a list of names. See [Heuristics](heuristics.md#fill_optional).

**Why does `bake` return an invalid record?**
`bake` does not validate overrides, and it probes validity only when it has a reason. Call `valid?`. See [`bake` vs `bake!`](bake-vs-bake-bang.md).

**Why did `name 'Ada'` leave `name` nil?**
There is no static shorthand. A declaration without a block carries no value and also suppresses inference. Write `name { 'Ada' }`. See [Definitions](definitions.md#attribute-blocks).

**Why does `label { "#{name}-x" }` produce a strange string?**
Blocks have no access to sibling attributes. `name` inside the block is read as a new empty declaration. Use a local variable in the `define` block, or an override. See [Definitions](definitions.md#what-a-block-can-see).

**Is there `sequence`, `transient`, `after(:create)`, `build_stubbed`?**
No. Sequences: a counter local at the top of the file, or `SecureRandom`. Transients: locals inside `define`. Callbacks: do the work in a block, or after the `bake!` call. `build_stubbed`: no equivalent. See [Migrating from factory_bot](migrating-from-factory-bot.md).

**Can I pass a block to `bake!`?**
You can; it is ignored.

**Where are definitions loaded from?**
`config.factory_bakery.definition_paths` when set. Otherwise `spec/bakery` or `test/bakery` when factory_bot is detected, else the first existing of `spec/factories`, `test/factories`, `factories`. See [Rails](rails.md#configuration).

## Values

**Why do two bakes collide on a unique column?**
Either a literal value was passed for several records, or the uniqueness is only enforced in a callback, a composite index or the database. Inference regenerates on a collision it can see: a `uniqueness` validator or a single-column unique index. See [Heuristics](heuristics.md#uniqueness).

**Why doesn't FactoryBakery pick an enum value that passes my validator?**
Enum and other domain values can change behavior, so FactoryBakery leaves that choice to your definition and does not search alternatives. The error and `FactoryBakery.explain(record)` show a copy-pasteable snippet naming the attribute. For example: `FactoryBakery.define(WebHook) { wildcard_web_hook { true } }`. See [ADR-0008](../adr/0008-user-chooses-domain-values.md).

**A column derived from another (a slug from a title) collides.**
The source must be filled. If `title` is optional with no validator, it is `nil` and every slug is `''`. Fill it (`fill_optional: [:title]`, or a definition). Name- and title-like strings already get a random suffix.

**The format validator fails to generate.**
The regex may be unsatisfiable or too exotic for `regexp_parser`. Supply the value. See [format exhaustion](../../skills/factory-bakery-diagnostics/references/diagnostics.md#format-exhaustion).

**My model validates against an app registry (providers, emoji, site settings).**
Inference cannot see it. Declare a value from the registry. See [Heuristics](heuristics.md#what-inference-cannot-know).

**A JSON or YAML text column has a validator that parses it.**
A text column cast to JSON by an index gets a JSON string. Other structured payloads need a block that returns the right shape. See [diagnostics](../../skills/factory-bakery-diagnostics/references/diagnostics.md#structured-text-columns).

**Can I make values repeatable?**
`srand(seed)`.

## Associations

**Why is `comment.post` nil?**
The plugin is not loaded, or the association is optional in `:required_only`. Load it: `config.factory_bakery.associations = {...}`. Use `:all` for optional edges. See [Associations](associations.md#modes).

**A validator compares `user_id` with another id and fails.**
Unsaved parents have `nil` ids. Use `association :user, persist: true`. See [Associations](associations.md#persist).

**Two edges to one class: `IncompletePersistenceError` after `persist: true`.**
Persist both edges, or declare the second. See [bake! verification](bake-vs-bake-bang.md#the-verification-step).

**`:reuse_non_unique` picked the owner's own parent.**
It can't see rules in custom validators. Use `strategy: :fresh` on that edge. See [Associations](associations.md#strategies).

**`CyclicAssociationError`.**
Two required edges loop. Declare one side (`parent { nil }`) or make it optional. A declared collection block must pass the owner (`bake(Child, parent: owner)`). See [Associations](associations.md#cycles-and-depth).

**A has_one is created by an `after_create` callback and I get a duplicate key.**
For gem-built children, the gem keeps the callback's row under `bake!`. For one you declared, drop the declaration and let the callback make it, or `skip` the edge.

**Do I get `create_list(:comment, 3, post: post)`?**
Use `association :comments, count: 3` inside the owner's definition, or `Array.new(3) { bake!(Comment, post: post) }` in the test.

**STI.**
The `type` column is never filled. Bake the subclass. For an abstract base with several subclasses, declare which one: `association :target, Subclass`, or define the base with `initialize_with(type: 'Sub')`.

**Polymorphic.**
Discovered from an `inclusion` validator on the type column or `as:` inverses. Otherwise declare `association :x, Klass`. See [Associations](associations.md#polymorphic-edges).

## Persistence

**Does `bake` write to the database?**
Not on its own, except for [raw-FK presence parents](associations.md#raw-fk-presence-parents), `persist: true`, and your own `bake!` calls in blocks.

**Does `bake!` roll back on failure?**
Yes, the whole graph, even inside an outer transaction. See [`bake` vs `bake!`](bake-vs-bake-bang.md).

**A view (read-only model).**
`bake` works. `bake!` raises `ReadOnlyTargetError`. See [Associations](associations.md#read-only-targets).

**A model whose `new` raises.**
Construction retries with `unscoped` and then without callbacks. See [Definitions](definitions.md#models-whose-new-raises).

**A side effect runs twice.**
The verified fallback may rebuild a record, so declaration blocks can run twice. Keep blocks free of non-database side effects, or guard them. See [Heuristics](heuristics.md#the-verified-fallback).

## Rails

**factory_bot and FactoryBakery both load my `spec/factories`.**
Move FactoryBakery to its own directory: `config.factory_bakery.definition_paths`. See [Migrating](migrating-from-factory-bot.md#step-2-set-up-side-by-side).

**My definition does not apply after a code reload.**
Class-keyed definitions point at the old class object. Reload definitions, or use a symbol factory. See [Rails](rails.md#things-to-know).

**Is it thread-safe?**
Per-bake state is fiber-local. Plugin and mapper registrations and `Associations` global settings are process-wide.

## Other

**Which Ruby and Rails?**
Ruby >= 3.2. Rails 7.1, 7.2, 8.0. Tested on SQLite, PostgreSQL and MySQL.

**Where is the glossary?**
[`GLOSSARY.md`](../../GLOSSARY.md).

**Where do I report a bug?**
`https://github.com/mohammed-io/factory_bakery/issues`. Include the exact message and the model. If a model's own rules are the cause, a definition line is the fix, not a bug.
