# Association benchmarks: query shape, allocations, memoization

Measured on the final A20 branch (`mohd/v0.0.2`, commit `b14b635` + this ticket).
Ruby 3.4.3, in-memory SQLite, `BUNDLE_GEMFILE=gemfiles/rails8.0.gemfile`
(ActiveRecord 8.1.2). 50 warmup iterations, 1000 measured iterations per
scenario. Allocations are `GC.stat(:total_allocated_objects)` deltas divided by
iterations; GC is disabled during the measured loop. Query counts come from
`sql.active_record` notifications (setup SQL is excluded); reflection scans
come from a benchmark-only probe prepended to the model classes' reflection
API.

Reproduce:

```bash
BUNDLE_GEMFILE=gemfiles/rails8.0.gemfile mise exec ruby@3.4.3 -- \
  ruby benchmark/associations_bench.rb
```

`BENCH_ITERATIONS` and `BENCH_WARMUP` override the iteration counts. The script
prints the table below, runs deterministic shape assertions, and exits
non-zero if any assertion fails. It was also run cleanly against
`gemfiles/rails7.1.gemfile` and `gemfiles/rails7.2.gemfile` (ActiveRecord 7.2.3);
the shape numbers are identical there and the allocation/throughput numbers are
within a few percent.

## Schema and scenarios

- `Author` — `name` (presence), `email` (presence + format), `metadata` (json).
- `Post` — `belongs_to :author, optional: false`, `has_many :comments`,
  `title` (presence + uniqueness), `slug` (uniqueness + format), `metadata`
  (json), `comments_count` (counter cache).
- `Comment` — `belongs_to :post, optional: false` **and**
  `belongs_to :author, optional: false` (the diamond), `body` (presence),
  `metadata` (json).
- `Widget` — `name` (presence + uniqueness), `code` (uniqueness + format),
  `quantity` (integer), `metadata` (json). No associations.

`Author` deliberately has no uniqueness validator on `email`: the diamond
builds two fresh authors in one graph, and two random short regex-generated
emails can collide inside that graph (a pre-existing edge case in the gem,
outside A20). Uniqueness is still exercised on `Post` and `Widget`, which are
the sole records of their class per bake.

Scenarios: plugin off (core heuristics), `define` + trait with the plugin off,
`:required_only` `bake` and `bake!` on the 3-level `Comment → Post → Author`
chain (plus the `Comment → Author` diamond), `:all` on `Post` with
`default_count` 1 and 3, and `:reuse` vs `:fresh` with the lookup rows present
and absent.

## Query shape (unchanged by memoization)

`cSEL`/`cINS` are the cold, probed single bake; `wSEL`/`wINS` are the warm
per-bake averages. Every number here is asserted by the script.

| scenario | cSEL | cINS | wSEL | wINS |
|---|---:|---:|---:|---:|
| core heuristics (plugin off) | 2 | 0 | 2 | 0 |
| define + traits (plugin off) | 0 | 0 | 0 | 0 |
| required_only chain `bake` | 2 | 0 | 2 | 0 |
| required_only chain `bake!` | 4 | 4 | 4 | 4 |
| `:all` `default_count=1` `bake!` | 4 | 4 | 4 | 4 |
| `:all` `default_count=3` `bake!` | 4 | 8 | 4 | 8 |
| `:reuse` rows present `bake!` | 2 | 1 | 2 | 1 |
| `:reuse` rows absent `bake!` | 6 | 3 | 6 | 3 |

Interpretation:

- `bake` never INSERTs, in every mode. `bake!` inserts exactly one row per
  generated node: 4 for the diamond chain, 4 for `:all count=1`, 8 for
  `:all count=3`. Autosave orders parents before children; no explicit
  topological sort or extra write is needed.
- With `:fresh` there are no parent lookups at all — the `SELECT`s are solely
  uniqueness probes (one per unique heuristic attribute at build time, and
  again when ActiveRecord validates on `save!`). That is why chain `bake!`
  has 4 SELECTs (2 build + 2 save validation) while chain `bake` has 2.
- `:reuse` with rows present does exactly two `SELECT`s (one per `belongs_to`
  edge) and a single INSERT — the `Comment`. With rows absent it falls back
  to fresh builds; the per-bake graph cache deduplicates the diamond's two
  `Author` edges, so 3 INSERTs rather than 4. Both paths are bounded and
  deterministic.
- No N+1 beyond the explicit uniqueness and reuse lookups was found. Query
  shape was identical before and after memoization, which is the important
  invariant: caching never traded a query for an allocation.

## Allocations and throughput — before vs after

Rails 8.0 gemfile. `scn/bake` is reflection scans per warm bake.

| scenario | scn/bake before → after | alloc/bake before → after | k ops/s before → after |
|---|---:|---:|---:|
| core heuristics (plugin off) | 5 → **0** | 868 → **747** (−14%) | 2.9 → **3.2** |
| define + traits (plugin off) | 5 → **0** | 441 → **359** (−19%) | 7.1 → **8.0** |
| required_only chain `bake` | 28 → **0** | 2394 → **1935** (−19%) | 1.3 → **1.6** |
| required_only chain `bake!` | 28 → **0** | 3288 → **2827** (−14%) | 0.6 → **0.8** |
| `:all` `default_count=1` `bake!` | 30 → **0** | 3440 → **2983** (−13%) | 0.6 → **0.7** |
| `:all` `default_count=3` `bake!` | 58 → **0** | 6134 → **5259** (−14%) | 0.4 → **0.4** |
| `:reuse` rows present `bake!` | 6 → **0** | 1678 → **1574** (−6%) | 1.0 → **1.0** |
| `:reuse` rows absent `bake!` | 21 → **0** | 2883 → **2532** (−12%) | 0.7 → **0.8** |

Timings are wall-clock and noisy; treat them as directional. The allocation
deltas are deterministic counters and the reflection scan counts are exact.

## What was memoized (and why it is safe)

1. **Reflection lists, per model class** — `lib/factory_bakery/reflection_cache.rb`.
   ActiveRecord caches its raw `reflections` hash, but
   `reflect_on_all_associations` rebuilds a filtered array every time. Core
   asked for the `belongs_to` list three times per bake (alias groups, FK skip
   set, plugin heuristics), plus `has_many`/`has_one` for counter caches, the
   full list for persistence verification and `:all`, and the plugin asked
   again for back-edge detection. All seven call sites now go through
   `ReflectionCache`. The arrays are stored on the model class itself, not in
   a global map, so a reloaded class drops its cache with it; concurrent
   first-bakes merely compute the same list twice (benign). Result: **28 → 0
   reflection scans per warm bake** on the chain, **58 → 0** on `:all count=3`,
   and query shape unchanged.

2. **Filler instances, per model class and attribute** —
   `FillerSelector.cached_for` in `lib/factory_bakery/attribute_fillers/filler_selector.rb`,
   used by `BakeTimeValues`, `BakeryBuilder#apply_confirmations` and
   `UniquenessEnforcer#regenerate`. Fillers capture schema/validator
   constraints at construction and are otherwise stateless — every `call`
   samples a fresh value. The same pair was resolved repeatedly (generation,
   confirmation check, uniqueness regeneration). The cache also lives on the
   model class. `ConfirmationFiller`, which has a mutable source-value setter,
   is deliberately not shared. Result: **−14% to −19% allocations** on the
   heuristic-heavy paths, with no change in generated values or queries.

The per-bake `BakeryBuilder`, `BakeTimeValues` and `BuildContext` state were
left untouched, as required: they hold the overrides, generated values,
build path and in-graph `:reuse` cache for one bake and must be fresh every
time.

## What was left alone (and why)

- **Uniqueness-enforcer `SELECT`s.** One uniqueness probe per unique heuristic
  attribute is unavoidable — the check must consult the database. `bake!`
  pays a second set when ActiveRecord validates on `save!`. Removing either
  would let invalid rows through; the benchmark asserts their exact count
  instead. No memoization of query results is safe here because the database
  can change between bakes.
- **`:reuse` lookup `SELECT`s.** One per eligible `belongs_to` edge is the
  defined strategy, not an N+1 accident. `order(primary_key).first` is
  deterministic; the in-graph cache already prevents repeated lookups for the
  same target within one bake.
- **`reflect_on_association` (singular).** ActiveRecord resolves this from its
  own reflection hash; instrumenting it showed no per-bake rescan cost worth
  wrapping.
- **`candidate_attribute_names` / `columns_hash.keys`.** Already backed by
  ActiveRecord's memoized schema; caching the key array would save a handful
  of allocations at the cost of another invalidation surface. Not a clear
  win — YAGNI.
- **`:all` graph size.** `default_count` and `max_depth` already bound it
  (8 INSERTs at `count=3`). Memoizing built children would change semantics
  (shared mutable records), so the only sharing is the explicit `:reuse`
  strategy and its per-bake graph cache.
- **Frozen model classes.** `cached_for` falls back to a fresh filler when a
  class is frozen; correctness over cache coverage.

## Verification

`bundle exec rspec --format progress`, all 560 examples, 0 failures on each of
`gemfiles/rails7.1.gemfile`, `gemfiles/rails7.2.gemfile` and
`gemfiles/rails8.0.gemfile`. The benchmark script exits 0 with all shape
assertions passing on all three.
