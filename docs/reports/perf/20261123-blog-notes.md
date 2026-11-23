# Performance: notes for the blog post

Raw material for the performance section of the FactoryBakery blog post. It is kept separate from the existing post draft. Each item gives the issue we found, how we found it, the numbers, and the fix (planned or done). Measurement details live in [20261123-baseline.md](20261123-baseline.md). The "after" column gets filled in once the fixes ship.

## The one-paragraph story

Measured honestly, FactoryBakery is 4–10x slower than factory_bot for unsaved records and 1.5–2.5x slower for saved ones. In real apps the gem itself is rarely the bottleneck: the shape of the object graph (how many parents get created and saved) and the app's own callbacks dominate by one to two orders of magnitude. The biggest surprises were three random-number generators per bake, a benchmark harness that flattered us, and an RSA key nobody asked for.

## Issues found (and what they taught us)

### 1. Three random number generators per bake

- **Issue:** to keep seeded runs reproducible, every top-level bake derived its own `Random` and then reseeded FFaker's global generator. Reseeding builds a new `Random`, and restoring FFaker's previous seed afterwards builds another one. That makes three Mersenne Twister initializations per bake.
- **Why it hurt:** `Random.new(seed)` costs 12–22 µs on Ruby 4.0, which was 22% of a flat-model bake.
- **How we found it:** `Random::Base#initialize` was the #1 self-time frame in stackprof.
- **Fix (planned):** one generator per bake, handed to FFaker directly instead of reseeding it. Measured −20–25 µs per bake (flat model −15%).
- **Lesson:** "seed it per call" sounds free. It costs 4 KB of Mersenne Twister state each time.

### 2. Our first benchmark was too kind to us

- **Issue:** the harness wrapped each call in a plain `transaction do … end`. Rails 7.1+ never materializes a savepoint inside a clean, joinable parent; it uses a `RestartParentTransaction` instead. So FactoryBakery's nested `requires_new` blocks looked free.
- **Fix:** open the outer transaction the way Rails' transactional fixtures do, `begin_transaction(joinable: false, _lazy: false)`. Now every `save!` from either library is a real SAVEPOINT/RELEASE, as in a real suite.
- **Bonus finding:** even then, FactoryBakery's extra savepoints (fallback attempts, nested parents) cost no SQL. Rails emits a SAVEPOINT only when a query runs inside it. A `belongs_to` chain under `bake!` writes 3 rows in 1 savepoint; factory_bot's `create` uses 3.
- **Lesson:** benchmark inside the same transaction shape your users run in.

### 3. Uniqueness checks are the real price of zero-config

- **Issue:** for every uniqueness-validated column FactoryBakery fills by itself, it copies the record (`dup`) and runs ActiveRecord's real uniqueness validator against the database. That is one SELECT per column, even for an unsaved `bake`. `bake!` then pays the same SELECTs again inside `save!`.
- **Numbers:** 44% of a validated-model bake, and 4 vs 2 SELECTs for `bake!` vs `create`. On Postgres, validated `bake` is 7x factory_bot `build`.
- **The trade-off:** factory_bot never checks; you write `sequence(:email)` and hope. FactoryBakery guarantees a value that is unique against the database. The check is cheap with a definition: give the column a value and the probe disappears (validated `bake` 506 → 190 µs).
- **Fix (planned):** C1, a direct `exists?` for plain validators (no record copy). Under consideration: C2, optimistic uniqueness for `bake!` (let `save!` validate, and retry on `:taken`).

### 4. We filled the timestamps ActiveRecord fills anyway

- **Issue:** `created_at`/`updated_at` are `NOT NULL` without a default, so the required-only rule counted them as required and generated random past times for them. That is wasted work: ActiveRecord stamps them on save. It also differs from factory_bot (nil on `build`, "now" on `create`).
- **Numbers:** −23 µs per record when skipped; −60 µs on a 3-record chain, −85 µs on a 4-record `has_many`.
- **Status:** proposed (it changes behavior, so it is the maintainer's call).

### 5. Re-extending every builder with the plugin DSL

- **Issue:** each bake did `builder.extend(DSLModule)`. That creates a fresh singleton class per builder, every time.
- **Fix (planned):** include the module once per builder class. −6 µs flat, −40 µs on a `has_many` graph (one builder per record).

### 6. Per-child work that is per-collection

- **Issue:** in `:all` mode every `has_many` child recomputed `association.scope_for_create`, which builds a relation each time: 10.6% of a has_many bake.
- **Fix (planned):** compute it once per collection.

### 7. The fallback rebuild is a second full bake

- **Issue:** when app-defined validation rejects the lean record, FactoryBakery throws it away and rebuilds with optional columns filled. That is +85% on such models (357 vs 194 µs). It is correct by design (ADR-0006); the cost is the price of not guessing.
- **Mitigation for users:** a definition that sets the field the custom validator wants skips the fallback entirely.

### 8. Real apps: graph shape beats micro-optimizations

- **Discourse:** an *unsaved* `bake(Post)` ran 148 SQL statements in 136 ms. Required-only auto-build created a separate fresh user for `post.user` and for `topic.user`, persisted raw-FK parents during the build, and each category's `after_create` added an "About" topic. Discourse's own fabricator shares one user. With `:reuse_non_unique` the same bake takes 41 ms and 18 statements, within 1.3x of `Fabricate`.
- **Mastodon:** `bake!(Account)` took 39 ms against `Fabricate(:account)` at 9 ms, with fewer SQL statements. The difference is `before_create :generate_keys` (2048-bit RSA, about 30 ms), which Mastodon's fabricator skips with canned keys. One definition line fixes it.
- **Lesson:** before optimizing the library, look at what the graph creates and which callbacks it fires. The fastest record is the one you don't create.

### Things we suspected and ruled out

- Memoizing "does this class have custom validation?": no measurable gain.
- One probe copy per record instead of per check: no measurable gain (one check per column anyway).
- Savepoints as a database cost: they are lazy and free unless a query runs inside them.

## Before / after (to fill in after Phase 3)

| scenario (SQLite) | before µs | after µs | vs factory_bot before → after |
|---|---:|---:|---|
| flat bake | 186.2 | | 4.43x → |
| validated bake | 506.3 | | 9.91x → |
| validated bake! | 752.9 | | 2.25x → |
| belongs_to chain x3 bake | 465.1 | | 4.40x → |
| has_many x3 bake | 770.5 | | 3.56x → |
| fallback rebuild bake | 357.3 | | 8.26x → |
