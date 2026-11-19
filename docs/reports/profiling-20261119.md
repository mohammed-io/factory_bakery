# FactoryBakery profiling report — 2026-11-19

Where the time goes in one `bake`, why af756ed is slower than 0711dce, and what to do about it.

- **Profiled snapshot (frozen):** commit `af756ed` at `.smoke-tests/gem-af756ed`
- **Baseline:** commit `0711dce`, extracted to `…/scratchpad/profiling/baseline-0711dce`
- **Ruby:** 3.4.3 (arm64-darwin), via `mise exec ruby@3.4.3`
- **DB:** in-memory SQLite via ActiveRecord 8.1.4.1
- **All scripts and raw outputs:** `/private/tmp/claude-501/-Users-mohammed-Projects-factory-bakery/d392862b-e1b0-40d7-a4d6-5ac4bd6be0b6/scratchpad/profiling/` (the "scratch dir" below)
- **Nothing in the gem was edited.** All experiments run with `-I <snapshot>/lib`; ablations are process-local monkeypatches.

Bench model: the same 7-column validated `BenchUser` as `bake_bench2.rb` (email/username/name presence+length, age numericality 18..120, color `/\A#[0-9a-f]{6}\z/`, nullable `bio`, defaulted `admin`). The associations scenario bakes a 3-model graph (`BenchBadge` →(required) `BenchEmployee` →(required) `BenchDept`, plus a presence-validated `has_one :bench_badge` on the employee) with the associations plugin in `:required_only` mode.

---

## 1. Headline numbers

`bake_bench2.rb`, single-shot as the maintainer runs it (GC on):

| commit | µs/bake | 
|---|---|
| af756ed | 143.3 – 146.6 |
| 0711dce | 94.2 – 100.0 |

That reproduces the reported ~139 vs ~97 µs: **af756ed is ~1.5× slower per bake, +81 allocs/bake (394 → 475).**

`bake_bench.rb` (adds `email format: /\A[^@\s]+@[^@\s]+\z/`): af756ed runs at **157 – 164 µs/bake**. 0711dce **cannot run it at all** — its hand-written regex synthesizer produces `"@^^@^^\t^"` and raises `FactoryBakery::Error` after 10 attempts. Part of af756ed's added cost is the correctness fix for exactly this class of regex (`#49/#65`).

### Scenario matrix (median of 7 reps × 2000 bakes, GC disabled during reps)

| scenario | af756ed µs | 0711dce µs | Δ | af allocs/bake | base allocs/bake |
|---|---:|---:|---|---:|---:|
| `bake` (7-col model) | **128.0** | **80.0** | +60% | 475 | 394 |
| `bake!` (persisted) | **281.4** | **235.8** | +19% | 670 | 581 |
| assoc `:required_only` (3-model graph) | **461.2** | **155.6** | **+197%** | 1580 | 652 |
| `fill_optional: true` | **114.1** | **90.4** | +26% | 457 | 406 |

Caveat on the assoc row: af756ed builds **4 objects** per bake (badge, employee, dept, plus the auto-built `has_one` badge — feature `#53` didn't exist in 0711dce), while 0711dce builds 3. Per object that is still **115.3 µs vs 51.9 µs (2.2× slower per object)**; like-for-like on 3 objects it is 461.2 vs ~(155.6 + 52) ≈ 208 µs. The graph case is where af756ed hurts most because every one of the nested bakes repeats the new per-bake bookkeeping *and* opens its own savepoint.

`fill_optional: true` being *faster* than plain `bake` on af756ed (114.1 vs 128.0) is diagnostic on its own: in full mode the FallbackBuilder skips the savepoint and the partition entirely (`savepoint_available?` → false), so those two steps cost the plain bake ~14 µs net.

Cold vs warm: the first bake of a fresh process costs **6.6 ms / 14.7k allocations** on af756ed (7.7 ms on 0711dce) — constraint reading, filler construction and regex tree compilation all happen once per class. Steady state is ~20× faster; warm all class caches before measuring anything.

---

## 2. Per-step breakdown of one bake (af756ed, `bake` scenario)

Instrumented by prepending timers around 30 pipeline methods (`prof_steps.rb`; two passes: clock-only and allocation-only). **Observer effect: the instrumented total is 183 µs vs 128 µs clean (+43%) — the per-step *percentages* are robust (cross-checked against stackprof below), the µs are inflated ~1.4×.** Numbers are *inclusive* (children counted inside parents); nesting is shown by indentation.

| step (af756ed `bake`) | µs/bake | % of instrumented total | calls/bake | allocs/bake |
|---|---:|---:|---:|---:|
| **total (clean, uninstrumented)** | **128.0** | — | — | **475** |
| cold first bake (once per class) | 6583 (µs, single) | — | 1 | 14 738 |
| 1 definition resolution (`BakeryBuilder.resolve`) | 0.4 | 0.2% | 1 | 1 |
| 2 `FallbackBuilder#build` (savepoint wrapper) | 182.4 | 99.7% | 1 | 695 |
| 2a `build_object` (bake + uniqueness) | 169.9 | 92.9% | 1 | 673 |
| 2b `fallback_needed?` (`valid?` gate) | 0.5 | 0.3% | 1 | 0 |
| 2c `adapter.transaction` (SAVEPOINT round-trip) | 179.0 incl. | — | 1 | 688 incl. |
| 3 `evaluate_declarations` | 1.0 | 0.6% | 1 | 4 |
| 4 `instantiate` → 4a `Construction.call` (`klass.new`) | 10.0 / 8.5 | 5.5% | 1 | 21 / 13 |
| 5 `compute_resolved_values` | 136.1 | 74.4% | 1 | 562 |
| 6 `alias_groups` (per builder instance) | 2.7 | 1.5% | 1 | 9 |
| 7 `guard_columns` (per builder instance) | 3.9 | 2.1% | 2 | 22 |
| 8 `candidate_attribute_names` → 8a `Mapper#attribute_universe` | 12.0 / **10.8** | 6.6% / 5.9% | 2 / 1 | 66 / **61** |
| 9 `declared_values` | 0.7 | 0.4% | 1 | 7 |
| 10 `plugin_heuristic_values` | 1.8 | 1.0% | 1 | 12 |
| 11 `counter_cache_values` | 1.2 | 0.7% | 1 | 9 |
| 12 `assign_values` (public_send setters) | 6.5 | 3.5% | 2 | 16 |
| 13 `apply_confirmations` | 6.8 | 3.7% | 1 | 18 |
| **14 `partition_candidates` (required-only split)** | **47.7** | **26.1%** | 1 | **211** |
| 14a `fill_required?` per attribute | 22.4 | 12.3% | 7 | 91 |
| 14b `RequiredAttribute.call` | 2.1 | 1.1% | 7 | 0 |
| 14c `needs_verification?` | 9.5 | 5.2% | 1 | 29 |
| 14d ↳ `Mapper#custom_validation?` | 3.7 | 2.0% | 1 | 2 |
| **15 `heuristic_values` (value generation)** | **119.0** | **65.0%** | 1 | **421** |
| 15a `BakeTimeValues#value_for` | 69.2 | 37.8% | 5 | 197 |
| 15b `BakeTimeValues#generate` | 66.3 | 36.2% | 5 | 187 |
| 16 `FillerSelector.cached_for` | 11.0 | 6.0% | **13** | 25 |
| 19 `StringFiller#call` (4 attrs: email, username, name, color) | 43.3 | 23.7% | 4 | 127 |
| 20 `IntegerFiller#call` (age) | 3.4 | 1.9% | 1 | 5 |
| 17 `Builder#constraints_for` (→ 17a Registry → 17b Mapper cache) | 19.3 / 15.7 / 9.2 | 10.5% | 9 | 81 / 63 / 18 |
| 17c `Mapper#record_dependent?` | 6.0 | 3.3% | **14** | 0 |
| 18 `run_after_instantiate` (plugin hooks) | 0.5 | 0.3% | 1 | 0 |
| 22 `UniquenessEnforcer#call` | 5.6 | 3.0% | 1 | 30 |
| 23 `Conditional.applies?` | 0.0 | 0% | 0 | 0 |
| 24 condition-cache invalidation / write / read | 0.8 / 0 / 0 | 0.4% | 2 / 0 / 0 | 2 / 0 / 0 |

Reading it:

- **The af756ed bake pipeline is now three, not one, "phases of record":** the savepoint-wrapped fallback attempt (2), the required-only partition (14), and generation (15). Steps 14+2c+8+17 alone — which did not exist in 0711dce — account for roughly **35–40% of a plain bake**.
- **`attribute_universe` is recomputed on every bake** (each `BakeryBuilder` memoizes it per *instance*, not per class): 10.8 µs, 61 allocations. It reads `columns_hash`, walks `klass.validators` to find virtual names, then subtracts guard columns/aliases/attachments. 0711dce's version was 0.7 µs — columns only.
- **The constraints chain re-runs per bake even on cache hits**: 9 `constraints_for` calls (partition + verification) each go through `MapperRegistry` → `mapper_for` → `Mapper#constraints_for` → `record_dependent?` → `cache_for` → hash `||=`. 14 `record_dependent?` and 26 `mapper_for` calls per bake (ruby-prof counts below) are pure lookup overhead.
- **Condition machinery costs nothing on this model** (0 `Conditional.applies?` calls — no `if:/unless:` validators), and the cache invalidation writes are ~0.8 µs / 2 allocations. On models *with* conditional validators the cache is a net win; the infra cost is small.
- **Uniqueness is cheap here** (5.6 µs) because BenchUser has no uniqueness validator; each heuristic attribute still pays a `uniqueness_validated?` → `validators_on` walk.

### bake! (persisted), af756ed, instrumented total 339 µs (clean 281)

The same steps as `bake`, plus: outer `adapter.transaction` + root save (the bake! contract), `adapter.save!` 123.2 µs (36%), `PersistenceVerifier` 1.2 µs, `ReadOnlyGuard` ~0.5 µs. The FallbackBuilder's inner savepoint adds only **3.4 µs** here (already inside the outer transaction — nested SAVEPOINT, not BEGIN/COMMIT).

### associations scenario (af756ed, instrumented total 573 µs, clean 461; 4 nested bakes)

| step | µs/bake top-level | calls (4 objects) |
|---|---:|---:|
| `plugin_heuristic_values` (nested belongs_to bakes) | 593.7 incl. | 4 |
| `run_after_instantiate` (has_one auto-build) | 220.1 incl. | 4 |
| `FallbackBuilder#build` (one per nested bake!) | 1240.4 incl. | 4 |
| `adapter.transaction` (**6 savepoints** per top-level bake) | 1797.5 incl. | 6 |
| `partition_candidates` | 80.1 | 4 |
| `candidate_attribute_names`/`attribute_universe` (re-run per object) | 43.2 / 37.8 | 8 / 4 |
| `custom_validation?` (per object) | 8.2 | 4 |

Each of the four nested bakes repeats the full per-bake bookkeeping and **opens its own SAVEPOINT**; two extra savepoints come from the has_one/FK-parent paths. 0711dce had *zero* transactions on the plain-bake graph path.

---

## 3. Where the calls and allocations actually go

### Exact call counts (ruby-prof, wall mode, 300 bakes — counts are exact; see §7 for why its µs are not)

| method | calls/bake (`bake`) | calls/top-level bake (assoc) |
|---|---:|---:|
| `MapperRegistry.mapper_for` | **26** | **58** |
| `Kernel#is_a?` | 113 | — |
| `Kernel#respond_to?` (+ AR's) | 98 + 10 | 283 |
| `Hash#[]` | 95 | — |
| `Mapper#cache_for` | 23 | — |
| `FillerSelector.cached_for` | 13 | 14 |
| `Mapper#record_dependent?` | 14 | 10 |
| `Mapper#constraints_for` | 9 | 4 |
| `ActiveModel::Attribute#with_value_from_user` (setters) | 10 | — |

`mapper_for` is called from *every* registry method (`constraints_for`, `record_dependent?`, `custom_validation?`, `attribute_universe`, `guard_columns`, `alias_groups`, `persistence_adapter`, `construct`, `uniqueness_validated?`, …). It's a one-element `mappers.find { supports? }` — cheap per call, but 26× per bake it shows up as the top *self-time* and top *allocation* frame in stackprof (`Enumerable#find` = 5.5–6% of wall samples, 19.4% of allocation samples) because each iteration re-enters `supports?` and `klass.is_a?` dispatch.

### Allocations (memory_profiler, steady state, 500 bakes)

- `bake`: **322 attributed allocations / 24.3 KB per bake**, retained ~0 (no leak; everything is gen-0 garbage).
- assoc: 1048 allocations / 86.3 KB per top-level bake.

Top allocation sites (`bake`):

| site | allocs/bake | note |
|---|---:|---|
| `bakery_builder.rb:506` — `normalize_keys` (`(hash || {}).transform_keys(&:to_s)`) | 12 | also #1 by memsize: 960 KB/500 bakes; called 4–5×/bake, allocates even for nil/empty hashes |
| `counter_cache_detector.rb:24` — `CounterCacheDetector.new(klass)` per `guard_columns` call | 12 | detector + arrays rebuilt per bake |
| `regex_generation/window.rb:11` — `Window.new` per generated regex | 10 | the color `#[0-9a-f]{6}` regex walk |
| `ActiveModel::Attribute::FromUser` | 10 | inherent AR cost of 5 attribute writes |
| `bakery_builder.rb:283/292` — `raw_taken_names`/`taken_names` (`flat_map` + `to_s`) | 8 | |
| `mapper.rb:288` — `validator_attribute_names` flat_map | 6 | inside every `attribute_universe` recomputation |

By class: Array 146/bake, Hash 72/bake, String 49/bake — the pipeline's intermediate arrays/hashes dominate; none retained.

### GC

- GC on vs off: 136.4 vs 128.0 µs → **GC ≈ 6% of wall time**; stackprof attributes ~7.6% to `(sweeping)+(marking)`.
- 0.007 minor GCs per bake (one per ~140 bakes), **0 major GCs** — everything dies young, the generational hypothesis working as intended. `total_freed ≈ total_allocated` per bake.
- GC.stat/ObjectSpace deltas over a run: no object-class growth, no retained-object creep.

---

## 4. What af756ed's review fixes cost vs 0711dce

Decomposition of the +48 µs/bake regression (GC-off, 128.0 vs 80.0), with each item ablation-measured (§5):

| source of regression | µs/bake (ablated) | notes |
|---|---:|---|
| savepoint-per-attempt (FallbackBuilder) | **7.4** | every plain `bake` now opens SAVEPOINT+RELEASE on the connection; 0711dce had none |
| per-instance `attribute_universe` (now validator-aware) | **9.3** | 0711dce: 0.7 µs columns-only, same result reused less often matters less; af756ed recomputes per builder |
| `mapper_for` × 26/bake (new partition/verification lookups) | **6.4** | 0711dce read constraints once per class at filler construction |
| required-only partition + `needs_verification?` incl. `custom_validation?` | ~10–15 net | *feature cost*: buys fewer generated values (5 vs 7 attrs) but pays per-attribute cache lookups |
| RegexGeneration rewrite (regexp_parser walk per value) | ~4 | per-string-attr cost rose 7.9 → 10.8 µs; **buys correctness** — 0711dce fails `bake_bench.rb` outright |
| condition cache infra + FillOptional/BuildContext bookkeeping | ~2 | condition cache is a win, not a cost, on conditional models |
| **total** | **~29–35 ablation-proven + ~10–15 feature cost** | ablations 'all' recover 25.9 µs; the remainder is intrinsic to required-only + verified fallback |

For the assoc graph, the same three fixes multiply: 4 nested bakes → 4 savepoints + 4 universe recomputes + 58 `mapper_for` calls → **~70 µs/object of new overhead** before any feature work.

---

## 5. Ablation results (each patch applied in-memory, methodology identical to the scenario bench)

`abl.rb <ablation> <scenario>`; "none" rows reproduce the scenario numbers.

| scenario | none | universe (A1) | mapper_for (A2) | no_savepoint (A3) | introspection (A4) | keys (A6) | all (A5) |
|---|---:|---:|---:|---:|---:|---:|---:|
| bake | 129.1 | 119.8 | 122.7 | 121.7 | **113.4** | 129.1 | **103.2** |
| bake! | 280.4 | 271.6 | 272.8 | 277.0 | 265.3 | — | 256.0 |
| assoc | 465.6 | 422.0 | 448.9 | 428.7 | **395.6** | 458.3 | **385.1** |
| fill_optional | 114.5 | 101.8 | 112.6 | 115.7 | **96.9** | — | 102.7 |

(µs/bake, median of 7. Allocations: 'all' on bake 475 → **326**; 'introspection' 475 → 380; assoc 1580 → 1149.)

- **A1 per-class memoized `attribute_universe`**: −9.3 µs (bake), −43.6 µs (assoc, 4 objects), −78/−210 allocations. Confirms the ~10 µs suspicion; it scales with graph size.
- **A2 resolve `mapper_for` once per subject**: −6.4 µs (bake), −16.7 µs (assoc), −78 allocations. Confirms the ~6 µs suspicion.
- **A3 no savepoint on the lean attempt**: −7.4 µs (bake), −36.9 µs (assoc — six savepoints), −3.4 µs (bake!, already inside a transaction).
- **A4 per-class caches for all three introspection reads** (universe + alias_groups + guard_columns, which also caches `CounterCacheDetector`): −15.7 µs / −12% (bake), −70 µs / −15% (assoc), −95 allocations.
- **A5 all combined**: bake 129.1 → **103.2 (−20%)**, assoc 465.6 → **385.1 (−17%)**, bake! 280.4 → 256.0 (−9%).
- **A6 `normalize_keys` fast-path**: time-neutral on bake, −7 µs and −46 allocations on assoc; a pure allocation win (also the #1 memsize site).

---

## 6. Low-level VM findings

### YJIT

Run: `mise exec ruby@3.4.3 -- bundle exec ruby --yjit -I lib bench_scenarios.rb …` (same effect with `RUBY_YJIT_ENABLE=1`).

| scenario | af756ed no-YJIT | af756ed YJIT | speedup | 0711dce YJIT |
|---|---:|---:|---:|---:|
| bake | 128.0 | **57.0** | **2.24×** | 43.4 (1.84×) |
| bake! | 281.4 | 128.3 | 2.19× | 103.9 |
| assoc | 461.2 | 208.5 | 2.21× | 73.8 |
| fill_optional | 114.1 | 55.4 | 2.06× | 44.3 |

**YJIT alone makes af756ed (57 µs) faster than 0711dce without YJIT (80 µs)** — it absorbs the entire regression. af756ed gains *more* than 0711dce (2.24× vs 1.84×) because its new overhead is exactly what a JIT eats for free: megamorphic-ish registry dispatch, repeated hash lookups, `respond_to?`/`is_a?` chains, `Enumerable#find` loops. Allocation counts are identical to the interpreter (YJIT compiles, doesn't de-allocate).

`RubyVM::YJIT.runtime_stats` after warmup (bake, `--yjit-stats`, 3000 bakes):

```
ratio_in_yjit:              91.5%      ← near-ideal: almost all executed insns run from JIT code
side_exit_count:            2,997      ← negligible; 99.9% are opt_eq on non-fixnums (String ==)
invalidation_count:             63     ← method_lookup 36, constant_state_bump 19: steady-state stable
num_send_megamorphic:         877 of 4,122,315 sends (0.02%)
code_gc_count:                  0      ← 2 MB code region, never reclaimed
compiled_iseq_count:          531
```

Nothing in the gem's code meaningfully *fights* YJIT. The minor fallback buckets worth knowing about:

- `invokeblock fallback … symbol: 31,967` — `map(&:to_s)`-style Symbol#to_proc blocks run through the interpreter entry; cosmetic at this scale.
- `iseq_missing_optional_kw: 7,232 / iseq_forwarding: 4,438` — our `*args, **kwargs` DSL-forwarding wrappers (the timer harness and `BakeryBuilder`'s kwarg-heavy call sites); each is one interpreter entry per call, not a hot loop.
- `Kernel#instance_variable_get` is the **top C call** (94,423 calls, 5.2% of C calls) — that's `cache_for`/`cached_for`'s `klass.instance_variable_get(:@factory_bakery_*)` cache pattern; YJIT can't inline ivar reads that go through the method call, another small argument for the A1/A2 caching fixes (or `defined?`-style guards).

### Inline caches, object shapes, constant caches

- `RubyVM.stat` deltas over 2000 steady-state bakes: `constant_cache_invalidations: 0`, `constant_cache_misses: 1`, `next_shape_id` unchanged, `shape_cache_size` unchanged. The gem's per-class `instance_variable_set` caches and `BakeryBuilder`'s fixed ivar-initialization order create **no shape or constant-cache churn** — ivars are always assigned in the same order per class, so one shape per role, reused every bake.
- Megamorphic call sites: `num_send_megamorphic` 0.02%. The dynamic `public_send("#{name}=", value)` setter sites stay polymorphic-but-not-mega (all targets are AR attribute writers). `method_missing` is used once per bake at most (`BakeryBuilder#method_missing` only fires for DSL declarations — none in the benchmark).

### Bytecode of a hot method

`RubyVM::InstructionSequence.of(BakeTimeValues.instance_method(:value_for)).disasm` (called 5×/bake):

```
0006 getinstancevariable   :@explicit_values, <is:0>   ( 33)[Li]
0009 getlocal_WC_0         key@1
0011 opt_send_without_block <calldata!mid:key?, argc:1, ARGS_SIMPLE>
0013 branchunless          23
0015 getinstancevariable   :@explicit_values, <is:1>
0018 getlocal_WC_0          key@1
0020 opt_aref              <calldata!mid:[], argc:1>[CcCr]
0022 leave
0023 getinstancevariable   :@values, <is:2> …          (same key?+[] pattern for @values)
```

What this shows: the ivar reads are **shape-guarded** (`<is:N>` inline slots — they stay fast precisely because BakeryBuilder/BakeTimeValues keep stable shapes); but each cache probe does **two hash operations** (`key?` then `[]`) per map, i.e. up to six lookups for a miss through three maps. A `fetch`-based or memoized-local rewrite would shave a lookup per probe — micro, but it's the same code path `value_for`'s 37.8% share lives on. The `compute_resolved_values` disasm (53 instructions) is dominated by `opt_send_without_block` merges of 4–5 hashes plus per-call `opt_getconstant_path <ic:0 BuildContext>` — the constant caches for `BuildContext` are hit every call and never invalidated (see above), which is why this stays cheap.

### Ractor

A bake is **not Ractor-safe, and shouldn't try to be**:

```
bake inside a Ractor: Ractor::IsolationError: can not set instance variables of classes/modules by non-main Ractors
```

That fires from `Mapper#cache_for` (`klass.instance_variable_set(:@factory_bakery_constraints, {})`) — per-class memoization is forbidden outside the main Ractor. Even if it were removed, ActiveRecord itself (connection pool, class-level state) is main-Ractor territory, and `Fiber[]` context state would need Ractor-local rework. Parallelism belongs at the *process* level (parallel test workers), where each process gets its own caches anyway; a single bake has no internal parallelism worth extracting (generation is CPU-trivial, graph building is inherently sequential). Not worth it.

---

## 7. Ranked recommendations

Each gain is ablation-measured (µs, % of that scenario's clean number). "Worth it" weighs risk and effort against the gain.

| # | recommendation | measured gain | risk | effort | worth it? |
|---|---|---|---|---|---|
| 1 | **Per-class memoization of the three introspection reads** — `attribute_universe`, `alias_groups`, `guard_columns` (which also caches `CounterCacheDetector`), keyed on the class like the existing `@factory_bakery_constraints` cache (drops with reload; skip for frozen classes) | bake **−15.7 µs (−12%)**, assoc **−70 µs (−15%)**, fill_optional −17.6 µs, −95 allocs | low — same lifetime pattern as the constraints cache; add reload test | small | **yes — do first** |
| 2 | **Resolve `MapperRegistry.mapper_for` once per subject** (per-class cache, invalidated on register/unregister by bumping a generation) — removes 26 finds/bake (58 in graphs) | bake **−6.4 µs (−5%)**, assoc −16.7 µs, −78 allocs | low — registry mutation is rare and testable | small | **yes** |
| 3 | **Gate the savepoint-per-attempt on "this attempt can write"** — only wrap the lean attempt in `adapter.transaction` when a definition block is present (declaration blocks may `bake!`) or an FK-presence parent may persist; the bare-benchmark path (no block, no plugin declarations) then skips it | bake **−7.4 µs (−6%)**, assoc **−36.9 µs (−8%)**; bake! unaffected (already transactional) | **medium** — it relaxes af756ed's rollback guarantee for the no-block case; the guarantee only matters when writes can occur, which is exactly the gate. Cover with a spec: declaration-block-with-`bake!` rollback still works | medium | **yes, with the gate carefully specified** — the blanket savepoint is the single most regressive review fix for graph bakes |
| 4 | **Ship/advertise YJIT** — document `RUBY_YJIT_ENABLE=1` (or `--yjit`) for test suites; the gem cannot force it | bake **128 → 57 µs (2.24×)**, assoc 461 → 208.5; beats the whole regression *and* the fixes above (57 µs < 0711dce's 80) | none functionally (CI should run both ways); +~2–5 MB code region, one-time ~120 ms compile | docs only | **yes — highest single lever, zero code** |
| 5 | **Micro-fixes in the value path** — `normalize_keys` fast-path (nil/empty/String-keyed hashes: −46 allocs/assoc bake, #1 memsize site); single-probe `fetch` in `BakeTimeValues#value_for`; skip `apply_confirmations`' full re-route when no `_confirmation` candidate exists (6.8 µs/bake) | ~8 µs/bake combined, −60 allocs | low | small | nice-to-have after 1–3 |
| — | Not recommended: per-bake `ConstraintSet`/partition result memoization (record-dependent by design), Ractor anything (§6), reducing `valid?` probing (only fires when verification is genuinely needed) | | | | no |

Combined realistic outcome: **1+2+3+5 land bake at ~100 µs and assoc at ~370 µs on the interpreter; with YJIT, ~50 µs and ~170 µs** — i.e. af756ed-with-fixes beats 0711dce in both absolute terms and per-feature-delivered, while keeping the correctness wins (regex generation, required-only defaults, verified fallback).

---

## 8. Teaching section — every tool, why, how to read it

Format: what it measures → command → excerpt → pitfalls → equivalents elsewhere.

### 8.1 The harness (benchmark discipline) — before any profiler

**Command** (scenario bench; 7 reps, GC disabled per rep, median):

```
mise exec ruby@3.4.3 -- bundle exec ruby -I <snapshot>/lib \
  <scratch>/bench_scenarios.rb bake af756ed
# → af756ed,bake,128.0,124.8,130.6,475,0.0,0.0,0.0
#    label ,scenario, median , min  , alloc-rep µs, allocs/bake, minorGC, majorGC, freed
```

**What it measures:** end-to-end wall time per bake (`Process.clock_gettime(CLOCK_MONOTONIC)` around N=2000 iterations) plus allocation/GC deltas via `GC.stat`. **How:** warm-up (≥200 bakes — fills per-class caches so you measure steady state, not first-touch compilation), then disable GC inside each timed rep to remove GC pauses from the sample, re-enable between reps, take the *median* of 7.

**Why this over `Benchmark.realtime`-style one-shot runs:** single-shot numbers wobble ±10% with GC placement (compare: GC-on bake = 136.4 µs, GC-off = 128.0, single-shot bake_bench2 style = 143–147). Median-of-reps with GC controlled is the smallest honest error bar; report it alongside the maintainer's original single-shot numbers so both are legible.

**Pitfalls:**
- *No warm-up* → you measure the 6.6 ms cold bake, not the pipeline.
- *GC enabled* → pauses land at random iteration boundaries; fine for "production-like" totals, noise for comparisons. Report both.
- *Too few iterations* → clock resolution floor (~µs on macOS) and scheduler noise dominate. 2000 bakes ≈ 0.26 s per rep is plenty.
- *Statistical noise:* on this machine run-to-run medians varied ~±3%. Anything below ~4% of total I treated as unproven and did not rank it.
- *Counting allocations:* `GC.stat(:total_allocated_objects)` is a monotone counter — safe to diff across a block even with GC on. `GC.disable` during the *allocation* rep guarantees nothing is collected mid-count (memory grows; fine for 2000 bakes).

**Equivalents:** Go `testing.B` + `b.ReportAllocs` (+ `benchstat` for run-to-run comparison); Python `pyperf` (`python -m pyperf timeit`) with `--rigorous`; Java JMH (`@Benchmark`, `gcProfiler` for allocation rates); JavaScript `tinybench`/`benchmark.js`; Rust `criterion` (which does the median-of-many and warns about outliers for you).

### 8.2 stackprof — the workhorse sampling profiler

**Commands** (produce dumps, then analyze; wall mode at ~100 µs/sample):

```
mise exec ruby@3.4.3 -- bundle exec ruby -I<stackprof-lib> -I lib -I . \
  <scratch>/prof_stackprof.rb bake af756ed <scratch>
# writes stackprof-af756ed-bake-{wall,cpu,object}.dump

mise exec ruby@3.4.3 -- ruby -I<stackprof-lib> <scratch>/stackprof_report.rb \
  <scratch>/stackprof-af756ed-bake-wall.dump
```

**What it measures / how:** a **sampling** profiler — a C-level signal handler pauses the VM every N µs (or every N allocations in `:object` mode) and records the current call stack. Overhead is a few %; numbers are *statistical estimates* (samples × interval), so a method needs ≳1% of runtime to register reliably.

**Why chosen over ruby-prof first:** sampling keeps the program's speed profile intact — you get honest percentages. `mode: :wall` (default, what an interactive user feels) vs `mode: :cpu` (excludes time blocked/sleeping — for single-threaded bakes they track each other; wall is the honest one here since GC counts). `mode: :object` counts allocation *sites*, not time.

**Reading it** (real excerpt, `bake` wall, af756ed):

```
-- top by SELF time --
5.2   (sweeping)      ← GC sweeping: 5% of wall time is the collector
6.0   Enumerable#find ← MapperRegistry.mapper_for's find loop
5.5   MapperRegistry.mapper_for
2.6   Mapper#custom_validation?
4.7   FillerSelector.cached_for
2.4   Mapper#record_dependent?
26.9  BakeTimeValues#generate (inclusive)  ← total column
```

*Self* = time in the frame itself; *total* = self + everything it called. Read them differently: rank leaves by **self** to find code to speed up; read **total** to decide *which pipeline phase* to attack. `(sweeping)`/`(marking)` frames are GC — a big share means an allocation fix beats a CPU fix.

**Flamegraphs:** `stackprof_report.rb` writes d3 flamegraphs from the dumps' raw samples:

- [flamegraph-af756ed-bake.html](/private/tmp/claude-501/-Users-mohammed-Projects-factory-bakery/d392862b-e1b0-40d7-a4d6-5ac4bd6be0b6/scratchpad/profiling/flamegraph-af756ed-bake.html)
- [flamegraph-af756ed-assoc.html](/private/tmp/claude-501/-Users-mohammed-Projects-factory-bakery/d392862b-e1b0-40d7-a4d6-5ac4bd6be0b6/scratchpad/profiling/flamegraph-af756ed-assoc.html)
- [flamegraph-0711dce-bake.html](/private/tmp/claude-501/-Users-mohammed-Projects-factory-bakery/d392862b-e1b0-40d7-a4d6-5ac4bd6be0b6/scratchpad/profiling/flamegraph-0711dce-bake.html)

Width = share of samples containing that frame; the flat top of `compute_resolved_values → heuristic_values → StringFiller` vs the wide-but-shallow `transaction → FallbackBuilder` band tells the af756ed story at a glance. Click a frame to zoom; `skip_common: true` strips the `Integer#times`-style scaffolding.

**Pitfalls:** too-high interval → missed short methods; too-low → overhead and pauses distort wall time; 2000 bakes ≈ 3000 samples gives ~±2% relative error on 1%-scale entries; `:object` mode's sample interval (every N allocations) means small methods under-report. Always warm up first or the dump is dominated by one-time compilation.

**Equivalents:** Go `pprof` CPU profile (`runtime/pprof`, sample-based; `go tool pprof -http` flame view) and its alloc profile = stackprof wall+object; Python `py-spy` (sampling, `--flame`); Java async-profiler/JFR (`-af:cpu,alloc,lock`); JS `--cpu-prof` / clinic; Rust `perf record` + `flamegraph` crate.

### 8.3 ruby-prof — exact call counts (and why you don't trust its µs)

**Command:**

```
mise exec ruby@3.4.3 -- bundle exec ruby -I<rubyprof-lib> -I lib -I . \
  <scratch>/prof_rubyprof.rb bake af756ed
```

**What it measures / how:** a **tracing** profiler — sets a `TracePoint`/C hook on every method entry and exit and *records every call*. Call counts are exact and complete; per-call timing is wall-clock between hooks.

**Why chosen despite overhead:** the questions "how many `mapper_for` per bake?" and "is `record_dependent?` called once per attribute or once per validator?" need *counts*, and only a tracer gives them without instrumenting each method by hand.

**Reading it** (real excerpt, `bake`, af756ed):

```
 %self  total   self  child  calls  name
 1.63  0.010  0.005  0.006   4200  Mapper#record_dependent?
 1.58  0.015  0.004  0.010   7800  <MapperRegistry>#mapper_for
 1.42  0.018  0.004  0.014   3900  <FillerSelector>#cached_for
```

`calls` ÷ 300 bakes: `mapper_for` **26/bake**, `record_dependent?` **14/bake**, `cached_for` **13/bake** — the counts that drove recommendations #1–2.

**Pitfalls — the observer effect is brutal:** the instrumented total was 0.278 s for 300 bakes ≈ **925 µs/bake vs 128 µs clean — a 7× slowdown**. Every send pays a hook, so time shifts toward send-heavy code; never report ruby-prof *percentages* as time attribution, and don't compare them to stackprof's. Keep runs short (300 bakes), warm up first, and use it for counts/structure only. (`eliminate_methods!` can hide framework noise but changes percentages — I didn't use it.)

**Equivalents:** Python `cProfile` (tracing, same observer-effect caveat — use for counts); Java's old `hprof=cpu=times` (nobody does this in production for the same reason); there is no direct Go equivalent because sampling is built into everything — `runtime/trace` with `go tool trace` is the closest for exact call/event streams.

### 8.4 memory_profiler — allocation attribution by file, line, and class

**Command:**

```
mise exec ruby@3.4.3 -- bundle exec ruby -I<memory_profiler-lib> -I lib -I . \
  <scratch>/prof_memory.rb bake af756ed
```

**What it measures / how:** wraps the block in an `ObjectSpace` trace-point that tags *every* Ruby-level allocation with its creation site, then aggregates. Distinguishes **allocated** (created during the block) from **retained** (still alive after GC at report time) — the leak detector.

**Why chosen over stackprof `:object` mode:** per-site and per-class attribution (stackprof object mode only samples and gives method names). Also gives *memsize* (bytes), which is how `normalize_keys` — time-trivial — turned out to be the **#1 byte** producer.

**Reading it** (real excerpt):

```
total_allocated: 161165 (322.3/bake)   ← attributed; GC.stat says 475/bake total
total_retained: 3 (0.01/bake)          ← no leak: everything is garbage by next GC

allocated by location:
 6000  bakery_builder.rb:506      ← normalize_keys; #1 by memsize too (960KB/500)
 6000  counter_cache_detector.rb:24
 5000  regex_generation/window.rb:11
 5000  active_model/attribute.rb:13  ← AR's own write path: not ours to fix
```

The gap between 322 (attributed) and 475 (GC.stat) is allocations made in C extensions and VM-internal objects that the tracer can't attribute — both numbers are true, different lenses.

**Pitfalls:** heavy overhead (~10× slowdown) — never mix with timing claims; runs must be short; warm up first or the report is dominated by first-touch caches; "retained" needs the report's own GC to have run (it forces one).

**Equivalents:** Python `tracemalloc` (per-site attribution, `start(25)` filtering) and `objgraph` for class histograms; Go doesn't need one — `pprof alloc_space` is native attribution; Java: JFR allocation events / async-profiler `alloc`; JS: Chrome heap snapshot / allocation timeline; Rust: `heaptrack` or `valgrind --tool=massif` (heap), dhat.

### 8.5 Vernier — modern sampling profiler with Firefox-Profiler output

**Command:**

```
mise exec ruby@3.4.3 -- bundle exec ruby -I<vernier-lib> -I lib -I . \
  <scratch>/prof_vernier.rb bake
mise exec ruby@3.4.3 -- ruby <vernier>/exe/vernier view <scratch>/vernier-bake.vernier.json
```

**What it measures:** stackprof-style low-overhead sampling, but it also records **per-line** events and emits a Firefox Profiler-format file. Its `view` prints an inverted tree; the `.vernier.json` opens in the Firefox Profiler UI (drag onto profiler.firefox.com) with timeline, flame chart, and sample table.

**Why chosen alongside stackprof:** cross-check (it independently ranked `Enumerable#find`, `record_dependent?`, `mapper_for` top — same answer from a different sampler is the cheapest way to rule out sampler bias), plus line-level attribution stackprof's text report doesn't give. Its output doubles as the "speedscope-format" artifact the stackprof version I have (0.2.28, no `print_speedscope`) couldn't emit:

- [vernier-bake.vernier.json](/private/tmp/claude-501/-Users-mohammed-Projects-factory-bakery/d392862b-e1b0-40d7-a4d6-5ac4bd6be0b6/scratchpad/profiling/vernier-bake.vernier.json)
- [vernier-assoc.vernier.json](/private/tmp/claude-501/-Users-mohammed-Projects-factory-bakery/d392862b-e1b0-40d7-a4d6-5ac4bd6be0b6/scratchpad/profiling/vernier-assoc.vernier.json)

**Excerpt** (`vernier view --top 14`):

```
| 13 | 2.5 | Enumerable#find
| 10 | 1.9 | Mapper#record_dependent?
| 10 | 1.9 | MapperRegistry.mapper_for
|  8 | 1.5 | Kernel#respond_to?
```

**Pitfalls:** samples in the hundreds for short runs (its default interval targets longer traces) — treat 1–2% entries as directional, exactly like stackprof.

**Equivalents:** this *is* the Ruby analog of Chrome's `--cpu-prof` output opened in the same UI; Java JFR + Firefox Profiler is the same pattern.

### 8.6 Targeted timing / ablation — the only proof a fix works

**Command:**

```
mise exec ruby@3.4.3 -- bundle exec ruby -I lib -I . \
  <scratch>/abl.rb introspection bake af756ed
# → af756ed,bake,introspection,113.4,111.5,112.2,380.0
```

**What it measures:** applies a monkeypatch implementing the *proposed fix* (per-class memoization, savepoint disabled, …) in-process, verifies a bake still produces a valid record, then re-runs the identical benchmark. The delta vs the `none` row is the fix's measured value — before anyone writes the real PR.

**Why it's necessary:** profilers tell you where time *is*; they don't tell you what removing it does (cache it and the call may just move; the "fix" may add allocations elsewhere). Ablation is the profiler equivalent of a controlled experiment. This is how the report's #1–3 got their µs/% numbers, and how "~10 µs universe" and "~6 µs mapper_for" from the suspicion list were confirmed (9.3 and 6.4).

**Reading it:** compare rows only within one scenario/methodology; sanity-fail loudly if bakes stop being valid (the script does). Beware ablations that change semantics rather than speed — A3 *does* change rollback semantics; its number is the *cost of the guarantee*, which is exactly what the maintainer needs to know to decide.

**Pitfalls:** monkeypatches can silently not apply (always assert the patched method is the one running — e.g. check the ivar cache is hit); GC noise identical to §8.1; run each ablation fresh-process so caches from one patch don't leak into the next.

**Equivalents:** Go's ablation is trivial (`pprof` + delete the call, `benchstat` the pair); Java JMH's `@Param` experiments; Python: patch + `pyperf` comparison; the general technique everywhere is "measure the counterfactual."

### 8.7 GC and VM statistics

**Commands** (inline in the scenario harness and `yjit_stats.rb`):

```
GC.stat(:total_allocated_objects)   # monotone allocation counter — safe to diff
GC.stat[:minor_gc_count/:major_gc_count]
ObjectSpace.count_objects           # live objects by type, snapshot
RubyVM.stat                          # constant-cache invalidations, shape ids
RubyVM::YJIT.runtime_stats           # ratio_in_yjit, side exits, invalidations
```

**Findings:** 475 allocs/bake, all short-lived (0.007 minor GCs/bake, **zero major GCs**, freed ≈ allocated); GC = 6–8% of wall; constant-cache and shape counters **flat over 2000 bakes** (no churn); YJIT stats in §6.

**Pitfalls:** `GC.stat` totals are process-lifetime counters — always report *deltas* around a region; `ObjectSpace.count_objects` right after `GC.start` vs not can differ wildly; never diff VM stats across a YJIT/interpreter boundary (different counters are meaningful).

**Equivalents:** `GODEBUG=gctrace=1` / `runtime.ReadMemStats`; Python `sys.gettotalrefcount`-style tooling and `gc.get_stats` (and the classic `tracemalloc`); Java `--Xlog:gc` + JFR/GC logs; V8 `--trace-gc` (Chrome DevTools memory pane).

### 8.8 Bytecode disassembly

**Command:**

```
RubyVM::InstructionSequence.of(BakeTimeValues.instance_method(:value_for)).disasm
```

**What it shows / why:** the actual instruction sequence a method compiles to — the ground truth under every profiler claim. In §6's excerpt: `getinstancevariable <is:0…5>` are *shape-guarded* inline-cache slots (fast precisely because our objects have stable shapes — connecting the "object shapes" story to code you can read), `opt_send_without_block <calldata!mid:key?>` are call sites with their inline caches, and the visible `key?`+`opt_aref` double lookup per hash is a real (small) inefficiency you can *see* rather than infer. Use it to validate a hot method's bytecode shape before micro-optimizing: if you see `opt_aref`/`opt_send` with `[CcCr]` fast-path markers, the interpreter is already running the fast path and wins must come from *fewer* operations, not different ones.

**Pitfalls:** bytecode is version-specific (3.4 output ≠ 3.3); never performance-tune *to* the disasm — it tells you what runs, the profiler tells you what matters.

**Equivalents:** `javap -c` / JIT's assembly output (`-XX:+PrintAssembly`); V8's `--print-bytecode` and `--print-opt-code` (TurboFan's optimized assembly is the analog of YJIT's machine code); CPython dis (`dis.dis`, and 3.13+'s `--specializing` bytecode is *exactly* the inline-cache story told in §8.8/§6); Rust/Go are already machine code — `go tool objdump`/`perf annotate`.

### 8.9 The VM concepts in plain terms

- **JIT (YJIT):** the VM compiles hot bytecode to machine code while the program runs, specializing it to observed types. Ruby 3.4's YJIT does this lazily and keeps a fallback to the interpreter. Analog: V8's TurboFan, the JVM's C2 (with the interpreter/YJIT split mirroring Java's tiers 0→3→4). *How to read our result:* `ratio_in_yjit 91.5%` says nearly all executed instructions ran compiled; the 2.2× speedup concentrated in exactly the dispatch-heavy overhead af756ed added — a JIT is the cheapest possible revenge on framework plumbing.
- **Inline caches:** each `some_obj.some_method` call site remembers the receiver's class and (pre-)resolved method after the first call, so later calls skip full lookup. Specialization levels: monomorphic (one class seen) → polymorphic (a few) → megamorphic (too many; falls back to full dispatch every call). Analog: CPython 3.13's specializing interpreter (`LOAD_ATTR` → `LOAD_ATTR_INSTANCE_VALUE`), V8's feedback vectors, the JVM's inline caches in the interpreter feeding speculative devirtualization. *Our code:* dispatch stays healthy — 0.02% megamorphic — but `Kernel#instance_variable_get`-based caches and `Enumerable#find` over a 1-element mapper list are *C calls* the JIT can't crack open, which is why fixing them in Ruby (memoize once per class) still pays.
- **Object shapes:** MRI 3.2+ tracks the *layout* of an object's instance variables (which ivars, in which order, in slots or an overflow table) as a "shape"; a stable ivar order lets ivar reads compile to fixed-slot accesses (`<is:N>` in the disasm). If objects of one class get ivars in ever-different orders, shapes proliferate and every read pays a shape check. Analog: V8's hidden classes/map transitions (identical concept, same name origin), JVM field layout (fixed at class load, so the problem doesn't exist there), CPython's `__slots__`. *Our code:* shapes are stable (`next_shape_id` flat over 2000 bakes, fixed ivar init order in `BakeryBuilder#initialize`), so there is nothing to fix — the check was still worth running because `instance_variable_set` on *classes* is the pattern that usually causes it.
- **GC generations:** MRI's generational GC promotes objects that survive a minor GC to an old generation; most Ruby DSL/framework objects die young, so young objects get cheap minor collections and old ones are swept in rarer major GCs. *Our result is the textbook healthy case:* 475 short-lived allocations per bake, 0.007 minor GCs/bake, zero majors, freed ≈ allocated — allocation *volume* costs ~6–8% wall in marking/sweeping, but nothing accumulates. Analog: Go's GC has no generations but targets exactly the same "most objects die young" assumption; the JVM's young (Eden/Survivor) vs old generations are the direct parallel; CPython's cyclic GC is generation-counting (`gc.get_count`) rather than copying/compacting.
- **Sampling vs tracing (the meta-lesson):** sampling profilers take a census (cheap, statistical, honest timings); tracing profilers take a census *and* collect a toll (exact counts, distorted timings). The workflow that survives contact with a real codebase is: benchmark harness → sampling profile → *ablation* to prove fixes → tracing/bytecode only for the specific question that needs exact counts or ground truth. Every mature ecosystem converges on this same shape: pprof/benchstat, py-spy/pyperf/tracemalloc, JFR/async-profiler/JMH, --cpu-prof/tinybench, criterion/perf.

---

## 9. Artifact index (scratch dir)

All under `/private/tmp/claude-501/-Users-mohammed-Projects-factory-bakery/d392862b-e1b0-40d7-a4d6-5ac4bd6be0b6/scratchpad/profiling/`:

| file | what it is |
|---|---|
| `bench_models.rb`, `bench_scenarios.rb` | scenario harness (µs + allocs/bake, median of 7) |
| `prof_steps.rb`, `steps-{af756ed,0711dce}-{scenario}-{time,alloc}.csv` | per-step instrumentation, both commits, both passes |
| `prof_stackprof.rb`, `stackprof-*.dump`, `stackprof_report.rb` | sampling profiles (wall/cpu/object) + analyzer |
| `flamegraph-af756ed-bake.html`, `flamegraph-af756ed-assoc.html`, `flamegraph-0711dce-bake.html` | d3 flamegraphs (open in a browser) |
| `prof_vernier.rb`, `vernier-bake.vernier.json`, `vernier-assoc.vernier.json` | Vernier profiles (Firefox Profiler format) |
| `prof_rubyprof.rb`, `rubyprof-af756ed-{bake,assoc}.txt` | exact call counts |
| `prof_memory.rb`, `memory-af756ed-{bake,assoc}.txt` | allocation attribution |
| `abl.rb`, `ablations.csv` | ablation experiments A1–A6 |
| `yjit_stats.rb` | YJIT runtime stats + VM stat deltas |
| `baseline-0711dce/` | extracted baseline commit used for every comparison |

## 10. One-paragraph summary for the PR description

af756ed regressed a plain bake from ~80 to ~128 µs (GC-off, median) and a 3-model association bake from ~156 to ~461 µs. Three of its review/feature additions are responsible for most of it, each measured by ablation: the savepoint-per-attempt around every lean bake (−7.4 µs plain, −36.9 µs per graph bake), the per-bake recomputation of the now validator-aware attribute universe (−9.3 µs, ×4 in graphs), and per-attribute registry lookups (`mapper_for` ×26/bake; −6.4 µs). The rest is intrinsic cost of required-only defaults, verified fallback, and a regex generator that — unlike 0711dce's — can actually satisfy real-world regexes. Per-class memoization of the three introspection reads, a resolved-mapper cache, gating the savepoint on "this attempt can write", and documenting YJIT (2.24×, 91.5% in-YJIT, which alone beats the old commit's interpreter speed) recover the regression with the correctness wins intact.
