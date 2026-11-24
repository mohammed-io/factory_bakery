# Associations: design study

Status: **proposal, revised after user review (2026-11-18).** Follow-up to the scope issue #1 deferred ("Out of Scope: associations").
Revision: associations ship as an **opt-in plugin** with modes `:none` / `:required_only` / `:all` (approaches C and B both kept), a factory_bot-style `association` DSL, and a per-association `strategy:` of `:fresh` / `:reuse`. §1–§3 are unchanged analysis; §4 is the revised decision.
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
- **Verdict:** contradicts the gem's "minimal valid object" heuristic identity as a *default*. **Revised: kept as the opt-in `:all` plugin mode, bounded by depth and inverse-edge rules (§4.3).** The `count:` option replaces the transients/callbacks dependency.

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

- Cheap, with fewer INSERTs. But it makes tests order-dependent and nondeterministic, couples them through shared rows, and turns `bake` into a DB read. That contradicts `bake` being DB-free (issue #1 story 13). **Rejected as a default. Revised: kept as the explicit `strategy: :reuse` for `belongs_to` only (§4.5).** It also fixes the diamond duplication in §3.8.

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

## 4. Decision (revised): an opt-in associations plugin

Per user review: associations are a **separate, opt-in plugin**, a self-contained module in its own folder, loaded explicitly. It offers three modes (`:none`, `:required_only`, `:all`), a factory_bot-style `association` DSL, and a per-association `strategy:` (`:fresh` / `:reuse`). Core stays heuristic-only. It gains only the guard-rails and bug fixes that are wrong *today* regardless of the plugin, plus a small hook API.

### 4.1 Core vs plugin split

| Concern | Lives in | Why |
|---|---|---|
| F8 overridden blocks don't run, F9 alias-group precedence | **core** | Precedence bugs in the existing DSL. They hurt hand-written associations today (F7). |
| F10 ambient build context + cycle/depth error | **core** | Hand-written nested `bake` calls overflow today. The plugin reads the same context. |
| STI column, FK + polymorphic pair not faked, counter caches (F3–F5) | **core** | These are filler correctness ("don't fake what can't be known"), not association building. Without the plugin, output must still be valid. |
| Plugin hook API (§4.6) | **core** | ~40 lines. Also the future home for sequences/transients plugins. |
| `association` reserved name | **core** | Without the plugin, `association :x` used to fall into `method_missing` and be **silently ignored** (its block was nil, so the declaration was skipped). It now raises: `BakeryBuilder#method_missing` asks `PluginRegistry.reserved_error_message`, which answers "`association` requires the associations plugin: require 'factory_bakery/associations'" while the plugin is not registered (`RESERVED_DSL_METHODS` in `plugin_registry.rb`). |
| Modes, `association` DSL, strategies, building, inverse binding | **plugin** | Everything that instantiates associated objects. |

Without the plugin, behavior equals the plugin's `:none` mode minus the DSL.

### 4.2 Loading and folder layout

```
lib/factory_bakery/associations.rb            # entry point: requires folder, registers plugin
lib/factory_bakery/associations/
  configuration.rb   # mode, strategy, max_depth, default_count, .with { } scoping
  dsl.rb             # `association` method mixed into the definition scope
  declaration.rb     # Struct: name, traits, factory, count, strategy, overrides, block
  planner.rb         # class → reflections to auto-build for the active mode (memoized per class)
  modes.rb           # MODES = { none: ->(r) { false }, required_only: ..., all: ... }
  resolver.rb        # :fresh / :reuse lookup for one reflection
  assembler.rb       # builds, binds inverses, assigns, checks cycles via core context
spec/factory_bakery/associations/*_spec.rb
```

- Plain Ruby: `require 'factory_bakery/associations'` registers the plugin on require, with the default mode `:required_only`.
- Rails: `config.factory_bakery.associations = { mode: :required_only }` makes the Railtie require it (ties into issue #9). Leaving it unset means no plugin.
- Modes are lambdas over a reflection, not classes. Three predicates don't earn a class hierarchy (YAGNI).
- The layout is self-contained, so extracting it to a `factory_bakery-associations` gem later is a move, not a rewrite. The hooks are the only coupling.

### 4.3 Modes

| Mode | Auto-builds (when not declared/overridden) | Never auto-builds |
|---|---|---|
| `:none` | nothing; only explicit `association` declarations | — |
| `:required_only` (default) | required `belongs_to` (validator or NOT NULL signal), recursively | optional `belongs_to`, `has_one`, `has_many`, through, HABTM |
| `:all` | every non-polymorphic `belongs_to` (optional too), `has_one` (1), `has_many` (`default_count`, default 1) | through / HABTM (the join is the `has_many`'s job), optional polymorphic |

All modes: a required polymorphic association raises an actionable error unless declared (§3.2).

Rules that keep `:all` bounded (the problems in §3.8 and §3.14):
1. **Never walk back the edge you came from.** Building `post.comments` binds each comment's inverse `belongs_to :post` to the owner (passed as an override), so the child never builds a second Post.
2. **Depth budget truncates `:all` to `:required_only`.** It does not raise. Past `max_depth` (default 2 for `:all`), only required `belongs_to` keep being built, because objects must stay valid. The required chain stays bounded by cycle detection (§3.1).
3. Cycles raise `CyclicAssociationError` with the path, unless an inverse closes the loop. Same rule in every mode.

Scoping, from most specific to least:
```ruby
FactoryBakery::Associations.mode = :required_only                 # global
FactoryBakery::Associations.with(mode: :all) { bake!(Post) }      # per call; ambient for the whole graph
```
Use a block scope rather than a kwarg: `**overrides` shares its namespace with model attributes (`factory_bakery.rb:30`). If a kwarg is ever wanted, use the reserved `_associations:` (model-bakery `_fill_optional` convention). Per-factory mode (`associations :all` inside `define`) is deferred until someone asks for it.

### 4.4 The `association` DSL

> Historical design. The shipped API passes target overrides in `with:` (`association :author, with: { name: 'Ann' }`), adds `persist:` and a positional target class, and names the strategy `:reuse_non_unique`. See the README's `association` DSL section.

```ruby
FactoryBakery.define(Post) do
  title { 'Hello' }

  association :author                                       # class from reflection; its factory + heuristics
  association :author, :admin, factory: :editor, name: 'Ann' # traits, named factory, overrides for the child
  association :category, strategy: :reuse                   # reuse an existing row (§4.5)
  association :comments, count: 3, body: 'nice'             # has_many; inverse bound to this post
  association :commentable, factory: :post                  # polymorphic: names the target
  association(:reviewer) { |post| FactoryBakery.bake(User, team: post.team) } # escape hatch, owner-aware

  trait :anonymous do
    author { nil }                                          # opt-out = existing attribute block
  end
end
```

Signature: `association(name, *traits, factory: nil, count: nil, strategy: nil, **overrides, &block)`.

- **Evaluated after instantiation**, so the owner exists. That fixes F11 and enables inverse binding. The plugin's `after_instantiate` hook does it (§4.6).
- `name` is checked against `reflect_on_association` **at bake time**, not at definition time, because definition files load before models (issue #1 story 8). An unknown name raises `FactoryBakery::Error`.
- It sits in the **declarations layer**: traits can redeclare (later wins). Call-site overrides of `author:` or `author_id:` suppress it (alias group, F9 fix). Mode auto-build stays in the heuristics layer.
- `count:` on a singular association raises. Overrides apply to every child.
- Persistence: `bake` builds unsaved. `bake!` relies on the root's autosave transaction (§3.9). No `strategy: :create` is needed.

#### Other DSL/API pieces: needed vs rejected

| Piece | Verdict | Why |
|---|---|---|
| `association(name, …)` | **needed** | Customizes one edge (traits, factory, overrides) without hand-writing `bake` calls, and is the only way to name a polymorphic target. |
| Owner block arg `{ \|owner\| … }` | **needed** | Children must reference their parent (F11). It is explicit, so no factory_bot `instance` magic. It is backward compatible because blocks with arity 0 keep today's behavior. |
| `count:` | **needed** | `has_many` in a single line. It replaces factory_bot's transient + `after(:create)` pattern, so transients and callbacks can stay deferred. |
| `strategy: :fresh \| :reuse` | **needed** (your ask) | Graph size and speed, plus shared lookup rows. See §4.5. |
| `Associations.with(mode:, strategy:) { }` | **needed** | A global mode can't vary per test. A kwarg would collide with attribute names. |
| `max_depth`, `default_count` config | **needed** | Bound `:all`. |
| `FactoryBakery.bake_list(target, n, …)` (core) | nice-to-have | `count:` uses it internally. Exposing it is cheap and useful outside associations. Separate ticket. |
| `strategy: :build/:create` (factory_bot meaning) | rejected | Autosave plus the parent's own `bake`/`bake!` covers it. For a persisted parent under `bake`, pass `author: bake!(User)`. Reusing the word for build/create would also clash with `:fresh`/`:reuse`. |
| `skip_association :x` | rejected | `x { nil }` / `x { [] }` already exists and composes with traits. |
| Implicit association by attribute name (factory_bot) | rejected | Modes already do this from schema signals. Name-based magic collides with real attributes. |
| `build_stubbed`-style stubs | rejected | §2 E. |
| Double-underscore reach-in (`author__name:`) | deferred | `association :author, name: …` covers it in definitions. Revisit if call-site demand appears. |
| Transients, callbacks | still deferred | `count:` plus the owner block cover the association use cases. |

### 4.5 Strategy: `:fresh` vs `:reuse`

The names are `:fresh` (rather than "always_fresh") and `:reuse` (rather than "first_or_create"). The behavior is not literally `first_or_create`: it checks the current graph first, and `bake` never creates rows. A literal name would mislead.

| | `:fresh` (default) | `:reuse` |
|---|---|---|
| Lookup | none | 1) an instance of the same class + factory + overrides already built **in this bake graph**; 2) `scope.where(column_overrides).order(primary_key).first`, where `scope` is the factory's class (STI-scoped automatically); 3) miss → fresh build |
| Under `bake` | builds unsaved | DB **read**. On a miss it builds unsaved (no write). |
| Under `bake!` | INSERT via root autosave | Reuses a row, or INSERTs via autosave on a miss |
| Determinism | full | `order(primary_key)` picks the oldest row deterministically. Results still depend on what earlier code inserted. |

Restrictions (fail loud):
- **`belongs_to` only.** Reusing a `has_one`/`has_many` child would rewrite *its* FK, stealing it from another owner and mutating shared data. Raise `ArgumentError`.
- **No traits with `:reuse`.** A trait can't be matched against an existing row, so a reused row would silently lack the trait's state. Raise. Overrides that map to columns are matched with `where`. A non-column override forces a fresh build.
- A required polymorphic association still needs `factory:`, which names the class to search.

Scoping: per association (`strategy: :reuse`) > `Associations.with(strategy: :reuse) { }` > global `Associations.strategy = :fresh`. The most specific setting wins, so a factory author's explicit choice on one edge isn't flipped by a test-wide default.

Interplay: `:all` combined with `strategy: :reuse` collapses most `belongs_to` fan-out (diamonds share one User). The counter cache on a reused parent increments, which is correct Rails behavior. Scoped uniqueness on children of a shared parent now matters (§3.6). The filler's existing uniqueness handling has to carry it [guess: collisions are possible on small value sets].

### 4.6 Plugin hook API (core)

Options:
1. **Prepend over `BakeryBuilder` private methods.** Zero core change, but every core refactor can silently break the plugin. Rejected.
2. **Explicit hook registry (recommended).** A small core change and a stable contract. Multiple plugins compose, so future sequences/transients plugins can reuse it.
3. **Builder subclass chosen by config.** Clean, but allows only one plugin at a time. Rejected.

```ruby
FactoryBakery.register_plugin(FactoryBakery::Associations::Plugin)
# Plugin responds to (all optional):
#   dsl_module                                   -> Module mixed into the definition scope
#   heuristic_values(model_klass, context, taken) -> Hash merged into the heuristics layer (mode auto-build)
#   after_instantiate(object, declarations, context) -> evaluates `association` declarations with the owner
```
`taken` is the set of names already covered by declarations, overrides and `initialize_with`, alias groups included. The core build context (F10) is passed in as `context`: stack, depth, and the graph-instance cache that `:reuse` uses.

### 4.7 Staged rollout

- **Stage 0 (core):** F8, F9, F10.
- **Stage 1 (core):** guard-rails F3–F5, plus the hook API and the `association` stub.
- **Stage 2 (plugin):** skeleton + `:none` + `association` for `belongs_to` (the tracer bullet), then `:required_only`.
- **Stage 3 (plugin):** collections (`count:`, owner block, inverse binding), then `:all`, then `strategy: :reuse`.

### 4.8 Ticket breakdown (tracer-bullet slices)

Each ticket is a vertical slice through the public API, with observable-behavior specs only (issue #1 testing decisions). Plugin specs `require 'factory_bakery/associations'` and declare `optional: false` explicitly (§3.15).

**Core**

**C1: Overridden declarations are not evaluated**
- `bake(User, account: a)` does not run the definition's `account { }` block (counter or side effect). The same holds for trait-declared attributes. Existing precedence specs stay green.

**C2: Association/FK alias-group precedence** (after C1)
- With `account { bake(Account) }` declared, `bake(User, account_id: 7).account_id == 7`. `bake(User, account: a).account_id == a.id`.
- Polymorphic: `commentable:` sets both columns. Overriding only `commentable_type`/`_id` suppresses a declared `commentable`.

**C3: Cycle and depth detection across nested bakes**
- Mutually recursive declarations raise `FactoryBakery::CyclicAssociationError` with the class path (no `SystemStackError`). Exceeding the max depth raises `FactoryBakery::Error`. The next independent `bake` succeeds after an error.

**C4: STI type column left to Rails**
- `bake(Admin).type == 'Admin'`, and `bake!(Admin)` reloads as `Admin`. The base class gets nil. An explicit `type:` override is kept.

**C5: belongs_to FK and polymorphic pair not faked**
- An optional `belongs_to` FK is nil, and `bake!` passes with SQLite `PRAGMA foreign_keys = ON` and a real FK. An optional polymorphic pair is nil. Non-FK integers are still filled.

**C6: Counter-cache columns not faked**
- `comments_count` is 0 or nil (per NOT NULL), never random.

**C7: Plugin hook API + `association` stub**
- Without the plugin, `association :x` in a definition raises an error that names the require.
- A test plugin registered in the spec can add DSL methods, contribute heuristic values (overridable by declarations and overrides), and act after instantiation with the owner.
- Two registered plugins compose.

**Plugin**

**P1: Plugin skeleton, `:none` mode, `association` on `belongs_to`** (after C1–C3, C7)
- Without the require: no plugin behavior. With it plus `mode = :none`: nothing auto-built.
- `association :account` builds an unsaved `Account` under `bake` (zero INSERTs). `bake!` persists both, and a child validation failure leaves no Account row.
- Traits, `factory:` and overrides are forwarded. An unknown association name raises at bake time. Call-site `account:`/`account_id:` win. `account { nil }` in a trait opts out.
- POROs: `association` raises clearly, because a PORO has no reflections.

**P2: `:required_only` mode** (after P1, C5)
- Required `belongs_to` is auto-built (validator or NOT NULL signal). Optional stays nil. The parent's registered factory applies.
- Mutual required with `inverse_of` closes the loop. Without it: `CyclicAssociationError` with an opt-out hint. Required self-reference gives a clear error.
- Required polymorphic without a declaration gives an actionable error. With `association :commentable, factory: :post` it passes.

**P3: Collections and owner-aware blocks** (after P1)
- `association :comments, count: 3, body: 'x'` gives 3 comments, all bound to the owner. With `:required_only`, no extra Post rows exist after `bake!`.
- `association(:reviewer) { |post| … }` receives the owner. `count:` on a singular association raises.
- `has_one` builds one record, bound to the owner.

**P4: `:all` mode** (after P2, P3)
- Optional `belongs_to`, `has_one` and `has_many` (`default_count`) are built. Through/HABTM and optional polymorphic are not.
- No back-edge rebuild (row counts asserted).
- Past `max_depth`, only required `belongs_to` are built, and every object stays valid (`bake!` passes on a 4-level schema).

**P5: `strategy: :reuse`** (after P1)
- An existing row is reused (no INSERT). On a miss: unsaved under `bake`, created under `bake!`.
- A diamond graph builds one shared parent. Column overrides are matched. Traits combined with `:reuse` raise. `:reuse` on `has_many`/`has_one` raises.
- Precedence: per association > `with` > global.

**P6: Scoping and Rails config** (after P2)
- `Associations.with(mode:, strategy:) { }` applies to the whole nested graph and restores the previous values after the block, even when the block raises.
- `config.factory_bakery.associations = { mode: … }` loads and configures the plugin (depends on issue #9's Railtie).

**Core, optional:** `FactoryBakery.bake_list(target, n, *traits, **overrides)`.

### 4.9 Open questions for the user

1. Default mode when the plugin is required: `:required_only` (recommended) or `:none`?
2. `:all` defaults: `default_count` 1 and `max_depth` 2. OK?
3. Strategy precedence: the per-association setting beats the `with` scope (recommended). Or should the test scope win?
4. Cycle default: **raise** (recommended), or nil one side and warn?
5. Should `if:`/`unless:` presence validators count as required (over-build, recommended)?
6. Plugin inside this gem behind a `require` (recommended for now), or a separate gem from day one?
