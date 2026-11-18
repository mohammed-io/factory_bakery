# Associations: design study

Status: **proposal, for review.** Follow-up to the scope issue #1 deferred ("Out of Scope: associations").
Baseline: commit `d1f5c5f` (feat: PORO targets) on `mohd/v0.0.2`. All `file:line` citations refer to that commit.

Evidence labels used below:

- **[code]**: read directly in the cited source.
- **[probe]**: checked by running a scratch script against `lib/` at `d1f5c5f` (ActiveRecord 8.1.4, in-memory SQLite, outside Rails). The script lives outside the repo. The results are quoted inline.
- **[known]**: documented framework or prior-art behavior, quoted from memory. Docs were not fetched for this study, so each such claim also carries a confidence level.
- **[guess]**: design reasoning that has not been verified.

---

## 0. How things work today (relevant facts)

| # | Fact | Evidence |
|---|------|----------|
| F1 | AR candidate attributes are **columns only**. Association names such as `account` are never visited by heuristics. | `bakery_builder.rb:178-179` [code] |
| F2 | The FK column `account_id` is an ordinary `:integer`. It routes to `IntegerFiller` and gets `rand(1..100)`. | `filler_selector.rb:167-168`, `integer_filler.rb:158-159` [code]; probe: `account_id => 59` [probe] |
| F3 | The STI `type` column is **not skipped**. It routes to `StringFiller` and gets a lorem word, **which overwrites the subclass name Rails set in `new`**. | `filler_selector.rb:165-166`, no inheritance-column check anywhere in `lib/` [code]; probe: `bake(Admin).type => "excepturi"`. A record persisted with such a type later raises `ActiveRecord::SubclassNotFound` on load [probe] |
| F4 | A polymorphic `commentable_type` gets a lorem word and `commentable_id` gets a random int. When the association is required, `bake!` raises `NameError: wrong constant name ipsum`. When it is optional, the garbage pair persists silently. | [probe] |
| F5 | A counter-cache column without a DB default gets a random int. | `has_default?` `filler_selector.rb:134-138`; probe: `comments_count => 47` [probe] |
| F6 | With `belongs_to_required_by_default = true` (the Rails 5+ app default), `bake!(User)` fails with `Validation failed: Account must exist`. In **plain ActiveRecord outside Rails, the default is false**, so the same bake passes and leaves a dangling `account_id`. | [probe]. Consequence: the gem's own spec suite (plain AR, `spec/support/macros/define_constant.rb:130-135`) does **not** exercise required belongs_to unless specs opt in. |
| F7 | Explicit associations **already work** through the declaration DSL: `define(User) { account { FactoryBakery.bake(Account) } }`. `bake!` persists both records, because AR's belongs_to autosave saves the new parent before the owner inside the root `save!` transaction. | `method_missing` `bakery_builder.rb:87-91`, `declared_values` `:198-202`, `bake!` `factory_bakery.rb:35-39`; probe: `[true, true, 1]` [probe] |
| F8 | Declaration blocks run **even when overridden** at the call site. `bake(User, account: a)` still executes the `account { ... }` block, which wastes a build, or does an INSERT if the block calls `bake!`. | `declared_values` evaluates every block, `bakery_builder.rb:198-202`; probe: call counter = 1 [probe] |
| F9 | An FK override **loses** to a declared association: with `account { bake(Account) }` declared, `bake(User, account_id: 999).account_id => nil`. The `account_id` key keeps its early hash position from the heuristic layer, and `account=` is applied after it. | `resolved_values` `bakery_builder.rb:142-146`, `apply_values` `:208-215` [code]; [probe] |
| F10 | Cyclic declarations cause unbounded recursion. `Account { users { [bake(User)] } }` combined with `User { account { bake(Account) } }` gives `SystemStackError`. The existing `BuildingInProgress` guard is **per builder instance** (`bakery_builder.rb:73-76`), and every `bake` creates a fresh builder (`factory_bakery.rb:32`), so the guard never fires across bakes. | [code] + [probe] |
| F11 | Declaration blocks take no arguments (`block.call`, `bakery_builder.rb:200`) and run **before** instantiation (`:78-81`). A block cannot reference the object being built, so it cannot bind a child's inverse `belongs_to` to its owner. | [code] |
| F12 | POROs: candidate attributes come from validators (`bakery_builder.rb:184-196`). A PORO with `validates :account, presence: true` gets a *string* in `account` (via `validator_routed_filler` → `string_filler`, `filler_selector.rb:88-90`). POROs have no `reflect_on_association`. | [code] |

Takeaway: the gem is *already* "column-only" by accident (F2), and that path is actively harmful in three places: STI (F3), polymorphic (F4) and counter caches (F5). Two precedence bugs (F8, F9) and the missing cycle guard (F10) affect hand-written associations today, before any auto-association feature exists.

---

## 1. Inventory: association shapes the gem must reason about

| Shape | What appears in the schema | What it means for baking | Auto-fill candidate? |
|---|---|---|---|
| `belongs_to` (required) | `x_id` FK column, plus a `PresenceValidator` on `:x` with `message: :required` that Rails adds when not optional [known, high] | Without a real parent, validation fails ("X must exist"). | **Yes.** This is the core case. |
| `belongs_to optional: true` | FK column, no validator | nil is valid. A random id dangles and breaks real DB FK constraints. | No. Leave nil. |
| `belongs_to` with a NOT NULL FK but `optional: true` | FK `null: false` | The DB rejects nil and the model accepts it. | Yes. Treat as required (column signal). |
| `belongs_to polymorphic: true` | `x_type` string + `x_id` | The pair must name a real class and a matching row. The target class cannot be inferred from the owner side. | Required: **cannot infer**, so explicit only. Optional: nil both. |
| `has_one` | FK on the *other* table | Nothing to fill on the owner. Valid unless someone writes `validates :x, presence: true`. | No (explicit only). |
| `has_many` | FK on the other table | Same as `has_one`. Building children multiplies the graph. | No (explicit only). |
| `has_many :through` | Join model + its FKs | Assigning the collection creates join rows on save. Through-of-through is read-only in places [known, medium]. | No (explicit only). |
| `has_and_belongs_to_many` | Join table, **no model** | Nothing to bake. Assigning the collection inserts join rows on save. | No (explicit only). |
| STI | `inheritance_column` (default `type`) | Must equal the baked class's `sti_name` (or nil on the base class). It must never be faked. | n/a. **Guard-rail.** |
| `inverse_of` | none | Lets Rails wire both sides in memory. This is the tool for closing cycles. | n/a (used by the cycle strategy) |
| `counter_cache` | `<children>_count` on the parent | Rails maintains it. A faked value is a lie. | n/a. **Guard-rail** (0 or skip). |
| `autosave:` / `validate:` options | none | `autosave: false` on `belongs_to` breaks the "root `save!` persists the graph" assumption. | Edge case: persist the parent explicitly. |

Detection signals, all available from AR reflection without a DB hit [known, high]:
`klass.reflect_on_all_associations(:belongs_to)`, `reflection.foreign_key`, `reflection.foreign_type`, `reflection.polymorphic?`, `reflection.klass`, `klass.inheritance_column`, `klass.validators_on(reflection.name)`, `klass.columns_hash[fk].null`. The counter-cache column comes from the child-side `belongs_to ... counter_cache:` option. It can be read through the parent's `has_many` reflection (`reflection.counter_cache_column` / `has_cached_counter?`) [known, medium: the exact private/public API varies by Rails version].

**Use validators to decide "required", not `reflection.options[:optional]`.** Rails materializes "required" as a `PresenceValidator` on the association name, whichever setting produced it: `belongs_to_required_by_default`, `required: true` or `optional: false`. This is the gem's heuristic-first identity applied to associations, and it automatically handles F6 (plain AR with a false default).

---

## 2. Approaches

### A. Column-only (formalize what exists, add guard-rails)

FKs are never filled with random ints, and associated objects are never instantiated. In concrete terms: the FK of every `belongs_to` gets nil from heuristics, polymorphic type and id get nil, the STI column is left to Rails, and counter caches are skipped.

- **Difficulty vs current architecture: trivial.** It adds one "skip set" to `heuristic_values` (`bakery_builder.rb:152-164`), next to the existing primary-key skip on line 156. Around 30 lines plus a cached reflection lookup per class.
- **Runtime cost:** ~0 (reflection scan per class, memoizable).
- **DB-touch profile:** none beyond today.
- **Blast radius:** `account_id` becomes nil instead of `1..100`. Nobody can reasonably depend on a random dangling id. Required belongs_to still fails exactly as today (F6), so this is no regression. It fixes F3, F4 and F5 outright.
- **Customization:** unchanged: a declaration, trait or override of `account`/`account_id` (once F9 is fixed).
- **Verdict:** necessary but not sufficient. Required belongs_to, the Rails default, still needs hand-written declarations in every model graph.

### B. Auto-build everything (factory_bot-style, recursive)

Every association gets an associated object, including has_many/has_one with N children.

- **Difficulty: high.** It needs: a recursion/build context that crosses `bake` calls (F10); owner-aware evaluation of association declarations after instantiation (F11 blocks this); inverse binding so children reuse the owner instead of growing new parents; count semantics for collections; a cycle policy for every pair of models.
- **Runtime cost:** multiplicative. With `has_many` × 2 at depth 3 you get 1 + 2 + 4 + 8 builds per bake, and auto-following `has_many` from children back up makes it unbounded without a depth budget.
- **DB-touch:** heavy on `bake!` (one INSERT per node). Even `bake` allocates the whole graph.
- **Blast radius:** large. Every existing `bake` of a model with associations changes shape and speed, and test counts like `Comment.count` shift.
- **Customization:** needs the full factory_bot vocabulary (`association`, strategies, `count`, transients, callbacks). Transients and callbacks are separately deferred, so this approach drags them in.
- **Verdict:** contradicts the gem's "minimal valid object" heuristic identity. Reject as a default.

### C. Hybrid / required-only (model-bakery-style)

Auto-build **only required `belongs_to`** (validator or NOT NULL signal), recursively, with a cycle guard. Everything else stays nil or empty unless declared. It includes A's guard-rails.

- **Difficulty: moderate.** It reuses existing seams:
  - Detection: a new `AssociationPlanner` (or similar) next to `FillerSelector`. Given a class, it returns `{required_belongs_to:, fk_skip_set:, sti_column:, counter_cache_columns:}`.
  - Build: for each required reflection not covered by overrides, declarations or `initialize_with`, value = `FactoryBakery.bake(reflection.klass)`. Going through the public entry point means the parent class's **registered factory and heuristics apply** (`BakeryBuilder.resolve`, `bakery_builder.rb:34-47`).
  - Persistence: **no topological sort needed.** Build the whole required chain *unsaved*. The root `save!` (`factory_bakery.rb:37`) autosaves new `belongs_to` parents first, inside its own transaction, so a failure rolls back the whole chain [known, high; F7 probe confirms the ordering]. The only exception is `autosave: false` on a reflection, where the builder persists that parent explicitly before the owner [guess: rare].
  - Precedence: the auto-built parent sits in the **heuristics** layer, so declarations, traits and overrides of either `account` or `account_id` suppress it (requires the F9 fix).
- **Runtime cost:** linear in the depth of the required chain (typically 1–3). Reflection scans memoized per class.
- **DB-touch:** `bake` touches none. `bake!` does one INSERT per required ancestor, in one transaction.
- **Blast radius:** medium-low. Only models whose bake *currently fails validation* change behavior, from failing to passing. Optional associations behave as in A.
- **Customization:** declare `account { ... }` in a definition or trait, or pass `account:` / `account_id:` at the call site. A global switch turns the feature off.
- **Verdict:** best fit.

### D. Reuse existing records ("pick any row")

For a required FK, use `reflection.klass.first` (or a random row), and create one only if the table is empty.

- Cheap, with fewer INSERTs. But it makes tests order-dependent and nondeterministic, couples them through shared rows, and turns `bake` into a DB read. That contradicts `bake` being DB-free (issue #1 story 13). **Reject.** It could come back later as an explicit opt-in (`_reuse: true`) if speed is ever a problem [guess].

### E. Stubbed ids (factory_bot `build_stubbed`-style)

Assign a fake id plus an in-memory parent marked persisted, without a DB write. Fast, but `bake!` cannot use it, and the stubbed parent lies about persistence. It adds a third strategy the API does not have. **Reject for now.**

### Comparison

| | A column-only | B auto-build all | C required-only | D reuse rows | E stubbed |
|---|---|---|---|---|---|
| Effort | XS | L | M | S | M |
| Passes Rails-default required belongs_to | ✗ | ✓ | ✓ | ✓ (if rows exist) | `bake` only |
| `bake` stays DB-free | ✓ | ✓ | ✓ | ✗ | ✓ |
| Graph size | 1 | exponential | required chain | 1 | required chain |
| Fits heuristic-first identity | partially | ✗ | ✓ | ✗ | partially |
| Blast radius | tiny | large | low | medium | medium |

---

## 3. Problem catalog

Each entry gives the failure, then the mitigation. "Stage" refers to the rollout in §4.

### 3.1 Cycles

**Direct mutual required:** `User belongs_to :account` and `Account belongs_to :owner, class_name: 'User'`, both required.
Naive recursion: bake(User) → bake(Account) → bake(User) → … → `SystemStackError` (the declared-block variant is already reproduced, F10).
Even with a guard, *persisting* such a graph needs one INSERT with a NULL FK. With NOT NULL on both FKs it is impossible without deferrable constraints.
**Mitigation:**
1. **Per-bake build context**, stored fiber-locally (`Fiber[:factory_bakery]` or `Thread.current`). It holds the stack of classes currently being built. It has to be ambient, not a parameter, because user-written declaration blocks call the public `FactoryBakery.bake` (F7) and must be covered too. Push and pop in `ensure`, so an exception never leaves stale state.
2. When an auto-build would push a class that is already on the stack, **close the loop**. If the reflection has an inverse (`reflection.inverse_of`, or `has_many`/`has_one` pointing back), assign the in-progress ancestor instance instead of building a new one. Otherwise **raise `FactoryBakery::CyclicAssociationError`** naming the path (`User → Account(owner) → User`) and telling the user to declare one side (`owner { nil }`) or make it optional.
3. Recommended default: **raise rather than silently nil one side.** Silent nil-ing produces objects that fail validation far from the cause. Close the loop only when Rails can wire it (inverse known).

**Indirect cycle** (A → B → C → A): the same stack check catches it at any depth. The error message prints the whole path.

**Self-referential:** `Node belongs_to :parent, class_name: 'Node'`.
- Optional parent (typical for trees): stage 1 leaves it nil. Fine.
- Required parent: every node needs a parent, so the chain is infinite by definition. The stack check sees `Node` on the stack and raises with the hint "declare `parent { … }` or make it optional". Do **not** point a node at itself automatically, because it hides schema mistakes [guess at user preference].

**Depth backstop:** `FactoryBakery.max_association_depth` (default 5 [guess]) raises `FactoryBakery::Error` when exceeded, even without a cycle (pathological long chains). Exceeding it is a design smell, so raise instead of truncating.

### 3.2 Polymorphic pairs

Failure today: random `commentable_type` → `NameError` on `bake!` when required, or a silent garbage pair when optional (F4).
**Mitigation:** stage 1 marks both `foreign_type` and `foreign_key` as non-fillable (nil). Stage 2: a required polymorphic association **cannot be inferred**. Finding candidate classes would mean scanning every model for `as: :commentable`, which needs eager loading and is ambiguous. So raise `FactoryBakery::Error` ("Comment#commentable is a required polymorphic association; declare it or pass `commentable:`"). Assigning an object through `commentable=` sets both columns consistently [known, high].

### 3.3 STI type column

Failure today: F3. The subclass name is overwritten by a lorem word, and the row is unloadable after persisting.
**Mitigation (stage 1):** add `klass.inheritance_column` to the heuristic skip set when the class `respond_to?(:inheritance_column)` and the column exists. Rails' `new` already sets the subclass's `sti_name`. On the base class the column stays nil, which is valid. Overrides can still set it explicitly.

### 3.4 has_many :through / HABTM intermediates

Never auto-filled. Explicit declarations work today: `tags { [FactoryBakery.bake(Tag)] }` assigns the collection, and `save!` writes the join rows [known, high for HABTM and simple has_many-through; medium for nested through, which can be read-only (`HasManyThroughNestedAssociationsAreReadonly`)].
Join-model required `belongs_to`s are satisfied by Rails when assigning through the collection, so no gem logic is needed [known, medium].

### 3.5 Counter caches

Failure today: F5 (`comments_count => 47` with zero comments).
**Mitigation (stage 1):** skip counter-cache columns from heuristics. If NOT NULL without a default, set 0. Detect from the parent's `has_many` reflections (`has_cached_counter?`/`counter_cache_column`) [known, medium on the API surface]. Fallback heuristic: `<has_many name>_count` columns [guess].

### 3.6 Uniqueness scoped by association

`validates :name, uniqueness: { scope: :account_id }`. Under approach C each bake gets a fresh parent, so scoped uniqueness passes trivially. Today it is "random id 1..100", so collisions are possible but the validation is not DB-backed unless the parent exists. With a **shared** parent (an override `account: a` reused across bakes), the uniqueness of `name` falls back on the filler's existing uniqueness handling (`unique_required`, `common_validators.rb:17-19`), which is unchanged. `has_one`-style `validates :user_id, uniqueness: true`: a fresh parent per bake satisfies it [guess, low risk].

### 3.7 Validation context and conditional validators

`validates :account, presence: true, on: :create` appears in `validators_on(:account)` with `options[:on]`. **Treat it as required**, because `bake!` creates. For `bake` it over-builds by one unsaved object, which is harmless.
`if:`/`unless:` validators: the condition cannot be evaluated before the object exists, so **treat them as required** (over-build) instead of under-building and failing. Document this. The user can opt out by declaring `account { nil }`.

### 3.8 Deep-graph explosion

Only possible with approach B or with explicit has_many declarations. Under C, the graph is the required-belongs_to closure: a DAG with fan-out = number of required FKs per class.
**Diamond:** `Order belongs_to :user, :shop` and `Shop belongs_to :user` builds **two** Users. That is correct but sometimes surprising. Mitigation (later, opt-in only): per-bake instance reuse by class (`_share: [User]`). Not in scope; neither prior-art tool does it by default [known, medium].

### 3.9 Persistence order, NOT NULL FKs, atomicity

- **Order:** let AR autosave do it. New `belongs_to` targets are saved before the owner; `has_many` children are saved after it [known, high; F7 probe].
- **NOT NULL FK:** satisfied because the parent is inserted first within the same `save!`.
- **Atomicity:** `save!` wraps the autosaves in one transaction. A child validation failure rolls back the inserted parents [known, high].
- **Current leak:** declaration blocks that call `bake!` (instead of `bake`) persist **outside** the root's transaction, so a root failure leaves orphan rows. Combined with F8 (blocks run even when overridden), that is an INSERT nobody asked for. **Guidance:** inside declarations, use `bake`, and let the root `bake!` persist. Fix F8 so overridden blocks never run.
- **`autosave: false` reflections:** the builder must `save!` the parent itself before the owner. That happens outside the root transaction, so document it, or wrap `bake!` in `transaction` [guess: wrapping is the cleaner fix].

### 3.10 Optional `belongs_to`: nil or filled?

**nil.** Filling optional FKs multiplies the graph and DB writes for no validation benefit. model-bakery leaves nullable FKs as None by default and has an explicit `_fill_optional` [known, high]. The equivalent opt-in here, if ever needed, would be `_fill_optional: [:account]` (deferred, YAGNI).

### 3.11 Dangling FK vs DB FK constraint

Today a random `account_id` passes model validation when optional (F6, plain AR) but fails `bake!` on Postgres/MySQL with `add_foreign_key`, raising `ActiveRecord::InvalidForeignKey`. SQLite enforces FKs only when `PRAGMA foreign_keys = ON`, which is why the gem's suite never sees it [known, high]. Stage 1 (nil FK) removes the whole class of failures.

### 3.12 POROs

No `reflect_on_all_associations`, so the association planner returns an empty plan (`respond_to?` guard), as the column-routing guards in `common_validators.rb:63-73` do. PORO behavior stays exactly as F12. An ActiveModel PORO with `validates :account, presence: true` keeps getting a string, which is acceptable because there is no schema to say it is an object [guess: revisit only if someone reports it].

### 3.13 Interplay with the DSL, traits and overrides

Rules (an extension of `resolved_values`, `bakery_builder.rb:141-146`):

1. An association name and its FK (and, for polymorphic, its type column) form an **alias group**. A value for any member at a higher layer suppresses every member at lower layers. This fixes F9: `bake(User, account_id: 999)` must not be clobbered by a declared or auto-built `account`.
2. Auto-build lives in the **heuristic** layer. It is suppressed by declarations (base or trait), overrides and `initialize_with` keys (as `heuristic_values` already skips `initialize_with` names, `bakery_builder.rb:153`).
3. **Overridden declarations don't run** (F8 fix). This matters once blocks build objects.
4. `account { nil }` in a definition or trait is the documented way to opt one association out of auto-build.
5. Traits that declare associations follow the existing "later wins" order (`bakery_builder.rb:99-107`), and the alias-group rule applies inside that order.

### 3.14 Owner-bound children (explicit has_many / has_one), the stage 3 blocker

`define(Post) { comments { [FactoryBakery.bake(Comment)] } }` together with stage 2 makes each Comment auto-build **its own** Post (a required `belongs_to :post`), and then gets reassigned to the outer Post on save, leaving orphan Posts behind. The root cause is F11: the block cannot see the owner.
**Mitigation options (stage 3, needs its own design pass):**
(a) evaluate association declarations **after** `instantiate` and pass the owner (`comments { |post| [bake(Comment, post: post)] }`, using block arity, which is backward compatible);
(b) the build context records "currently building Post X via `comments`", so a nested `bake(Comment)` pre-binds the inverse `belongs_to` (`reflection.inverse_of`) to X automatically;
(c) sugar: `comments(count: 2)` implemented as `owner.comments.build(attrs)`, so Rails sets the inverse.
Recommendation: (a) first, the smallest change. (b) only if (a) proves too verbose.

### 3.15 Gem test-suite blind spot

F6: plain AR defaults `belongs_to_required_by_default` to false. Specs for this feature must declare `belongs_to :x, optional: false` (or set the flag in a `before`/`after` pair) explicitly, or they will pass vacuously.

### 3.16 Prior art

| Concern | model-bakery (Python/Django) | factory_bot (Ruby) |
|---|---|---|
| Default for FK | Auto-creates related objects for **non-null** `ForeignKey`/`OneToOneField`, recursively. Nullable FKs are left `None` unless `_fill_optional`. [known, high] | No implicit fill *unless* the factory declares an attribute whose name matches a factory (implicit association) or uses `association :x`. [known, high] |
| Unsaved vs saved | `baker.prepare` builds unsaved. Related FKs are also prepared, not saved, unless `_save_related=True`. [known, medium-high] | `FactoryBot.use_parent_strategy` (default true since v5): `build` builds associations, `create` creates them. [known, high] |
| has_many / M2M | M2M not filled unless `make_m2m=True`. Reverse FKs are never auto-filled. Related sets via `related()` in recipes. [known, high] | Explicit: transients + `after(:create)` callbacks, or `association` inside a has_many block, or `create_list`. [known, high] |
| Polymorphic / generic | `GenericForeignKey` not auto-filled. You pass `content_object=`. [known, medium] | `association :commentable, factory: :post`, explicit. [known, high] |
| Cycles | No documented guard. Django schemas rarely have mutual non-null FKs. Self-referential non-null FK behavior: **unknown** [low confidence]. | No guard: `SystemStackError`. The documented fix is `instance` / `inverse_of` references in the association block (`association :author, posts: [instance]`) [known, medium]. |
| Customization | Double-underscore kwargs reach into related objects (`baker.make(Order, customer__name='x')`). Recipes with `foreign_key(recipe)`. [known, high] | `association :author, factory: :admin, strategy: :build`, traits on associations. [known, high] |

FactoryBakery's closest kin is model-bakery: auto-fill only what the schema says is required, and make everything else explicit. The double-underscore reach-in is a nice later idea (`bake(Order, account__name: 'x')`) but YAGNI for now.

---

## 4. Recommendation

**Approach C (required-only hybrid), shipped in stages, with A's guard-rails first.** It is the smallest change that makes `bake!` pass on Rails-default schemas, it keeps `bake` DB-free, and it matches the gem's identity: the validators and the schema say what is required, and the gem fills exactly that.

### Staged rollout

- **Stage 0: fix today's hand-written association bugs (independent, ship first).** F8 (overridden blocks don't run), F9 (alias-group precedence), F10 (ambient build context + cycle/depth error). These hurt users of the DSL now, and stage 2 builds on all three.
- **Stage 1: column guard-rails (approach A).** Nil FKs for every `belongs_to`, nil polymorphic pairs, untouched STI column, counter caches 0 or skipped.
- **Stage 2: required `belongs_to` auto-build.** Validator or NOT NULL signal; unsaved on `bake`, autosaved atomically on `bake!`; loop closing via inverse, otherwise `CyclicAssociationError`; required polymorphic raises a clear error.
- **Stage 3: explicit deep build (separate design pass, not scheduled).** Owner-aware association blocks (§3.14 a). Collection sugar only if real demand appears.

### Config surface (minimal)

```ruby
FactoryBakery.associations = :required   # default from stage 2; :off restores stage-1 behavior
FactoryBakery.max_association_depth = 5  # backstop, raises when exceeded
```

- No `:all` mode. It would be approach B, which this study rejects.
- **No per-bake kwarg yet.** `**overrides` shares one namespace with model attributes (`factory_bakery.rb:30`), so a kwarg named `associations:` could collide with a real column. If one is ever needed, use a reserved underscore prefix (`_associations: :off`), following model-bakery's `_fill_optional`/`_save_related` convention. Per-association opt-out already exists: `account { nil }` or `bake(User, account: nil)`.

### Ticket breakdown (tracer-bullet slices)

Each ticket is a vertical slice through the public API (`bake`/`bake!`/`define`) with observable-behavior specs, in line with issue #1's testing decisions.

**T1: Overridden declarations are not evaluated** (stage 0)
- `bake(User, account: a)` does not execute the definition's `account { }` block (observable via a counter or a side effect).
- Same for overrides that suppress a trait-declared attribute.
- Existing precedence specs stay green.

**T2: Association/FK alias-group precedence** (stage 0, depends on T1)
- With `account { bake(Account) }` declared, `bake(User, account_id: 7).account_id == 7`.
- `bake(User, account: a).account_id == a.id` regardless of the heuristic FK.
- Polymorphic: overriding `commentable:` sets both type and id. Overriding only `commentable_type`/`commentable_id` suppresses a declared `commentable`.
- PORO and non-association attributes are unaffected.

**T3: Cycle and depth detection across nested bakes** (stage 0)
- Mutually recursive declarations raise `FactoryBakery::CyclicAssociationError` whose message contains the class path. No `SystemStackError`.
- Nesting deeper than `max_association_depth` raises `FactoryBakery::Error`.
- Non-cyclic nested bakes (User → Account) still work.
- After a raised error, the next independent `bake` succeeds (context cleaned up in `ensure`).

**T4: STI type column left to Rails** (stage 1)
- `bake(Admin).type == 'Admin'`. `bake!(Admin)` reloads as `Admin`.
- `bake(User)` (base) has nil type.
- `bake(Admin, type: 'User')` keeps the override.

**T5: belongs_to FK and polymorphic pair are not faked** (stage 1)
- Optional `belongs_to`: `bake(User).account_id` is nil, and `bake!` passes with a DB FK constraint present (SQLite `PRAGMA foreign_keys = ON` in the spec).
- Optional polymorphic: `commentable_type` and `commentable_id` are both nil. `bake!` passes.
- A plain integer column that is not an FK is still heuristically filled.

**T6: Counter-cache columns not faked** (stage 1)
- `bake(Post).comments_count` is 0 or nil (per NOT NULL), never random, when `Comment belongs_to :post, counter_cache: true`.

**T7: Required belongs_to auto-built** (stage 2, depends on T2, T3, T5)
- With `optional: false` (explicit in the spec, see §3.15), `bake(User).account` is a new, unsaved, valid `Account`, and `bake` performs zero INSERTs.
- `bake!(User)` persists both records. If the User fails validation, no Account row remains (atomicity).
- A NOT NULL FK with `optional: true` is also auto-built.
- The parent class's registered factory and traits-free definition apply (`define(Account) { name { 'Acme' } }` → `'Acme'`).
- `account { nil }` in a definition and `bake(User, account: nil)` both suppress auto-build.
- `FactoryBakery.associations = :off` restores T5 behavior.
- POROs: no change, no error.

**T8: Cycles in auto-build** (stage 2, depends on T3, T7)
- Mutual required `belongs_to` with `inverse_of` closes the loop in memory, and `bake` succeeds without building a second root.
- Without an inverse: `CyclicAssociationError` naming both reflections, with an opt-out hint.
- Required self-referential `belongs_to`: a clear error with a hint.

**T9: Required polymorphic gives an actionable error** (stage 2, depends on T7)
- `bake(Comment)` with required `belongs_to :commentable, polymorphic: true` raises `FactoryBakery::Error` that names the association and suggests a declaration or override.
- With `commentable { bake(Post) }` declared, `bake!` passes and the type is `'Post'`.

**T10 (not scheduled): owner-aware association blocks**, stage 3, needs a grilling/design pass first (§3.14).

### Open questions for the user

1. Cycle default: **raise** (recommended) or **nil one side and warn**?
2. Should `if:`/`unless:` presence validators count as required (over-build, recommended)?
3. Is the stage-2 default `:required` acceptable as a behavior change in a 0.0.x release, or should it ship `:off` by default for one version?
