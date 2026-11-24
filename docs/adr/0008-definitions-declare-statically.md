# ADR-0008: Definitions declare statically; only values are dynamic

- Status: accepted (2026-11-24)
- References: [ADR-0002](0002-heuristic-first-verified-generation.md), [ADR-0006](0006-required-only-baking-and-verified-fallback.md), [performance baseline report](../reports/perf/20261123-baseline.md), [Definitions guide](../guide/definitions.md)

## Context

A `FactoryBakery.define(Model) { ... }` block is not stored as data. The gem keeps the block and runs it with `instance_eval` on every bake (and runs each requested trait's block after it). Each declaration line (`name { ... }`, `skip :x`, `association :y`) only records a pair `[name, value_block]`. The value blocks run later, when a value is needed.

So a definition has two layers:

- **The declaration layer**: the outer `do ... end` of `define` and of each `trait`. It decides *which attributes are declared, in which order, with which `skip`s and plugin declarations.*
- **The value layer**: the inner `{ ... }` blocks. They decide *what value* an attribute gets for this bake.

Because the declaration layer is ordinary Ruby run fresh each time, nothing today stops it from changing between bakes, for example `count { 3 } if ENV['WITH_COUNT']`. That freedom costs performance. Every bake re-runs the declaration blocks, allocates a pair and a name string per declaration, and rebuilds the per-bake name lists (`declared`, `explicit`, `suppression_seeds`, `raw_taken`) from them. The class-level facts (constraints, partitions, validators, mapper) are already cached per model class; the declaration layer is the largest per-bake piece that is not.

## Decision

1. **The declaration layer must be static.** A `define` block and a `trait` block must declare the same attributes, in the same order, with the same `skip`s and plugin declarations, every time they are evaluated. Their shape is decided by the code alone, never by runtime state: environment variables, the clock, randomness, database contents, global or thread-local state, or counters.
2. **Dynamic behavior belongs in the value layer.** A value block may read anything, call anything and return anything. `name { ENV['X'] ? 'a' : 'b' }` and `count { rand(1..10) }` are fine (the attribute is always declared; only its value varies); `name { 'a' } if ENV['X']` is not.
3. **What counts as static.** A loop or condition over a fixed literal or constant is static (`%i[a b].each { |n| add_attribute(n) { 1 } }`). A condition that can differ between two bakes in the same process is not.
4. **The declaration layer contains only declarations.** Code in a `define` or `trait` block that is not a declaration (a local computed from runtime state, `id = SecureRandom.hex` followed by `name { id }`, a `puts`, a counter bump) runs once, when the layer is recorded, not on every bake. Put it inside the value block.
5. **The contract permits caching, and the gem caches.** The declared pairs of a definition (base layer) and of each trait are recorded once (`DeclarationSet`) in a `DeclarationCache` that hangs off the definition's own block, along with each requested composition of base and traits. Per-call overrides are not cached: `BakeryBuilder::Names` combines them with the cached lists on every bake. Defining the target again installs a new block, so the old cache becomes unreachable; nothing is invalidated by hand. Together with the per-class cache of model facts (`ClassCache`) the layers nest: class facts, then the definition, then its traits, then the call's overrides.
6. **Layers that cannot be reused are evaluated on every bake, as before.** A layer is not recorded when it made a plugin declaration (`association`, an attachment declaration: the plugin replays its own entries each build), when it called `initialize_with` (its values are read as given), when its block raised, or when the block is frozen and cannot carry a cache. Plugin declarations made inside an attribute *value* block are recorded late and stay read live.
7. **Not enforced.** The gem does not detect a dynamic declaration layer. A definition that varies its declarations between bakes, or computes state at the declaration layer, gets the first bake's result until the target is defined again (the gem's own `reset_cache!` does not touch it). A definition author who needs a different shape declares a trait or a second definition (a named factory) instead.

## Consequences

- The Definitions guide and the migration skill state the rule and list anti-patterns, so definitions written from now on, and ones translated from factory_bot, follow it.
- factory_bot's own factories already declare statically: attribute lists are fixed when the factory is defined, so a 1:1 translation normally satisfies the rule. Conditionals in a factory body, which factory_bot would also evaluate once at load, must be moved into value blocks or traits.
- Authors lose the ability to make a definition declare a different attribute set per environment. The replacement is a trait selected at the call site, or a value block that returns the environment-dependent value.
- Measured on the synthetic benchmark (SQLite, Ruby 4.0.1): a model with a definition allocates 20 fewer objects per bake (270 to 250 for `bake`, 638 to 618 for `bake!`); models without a definition allocate the same or slightly fewer (227 to 225, 694 to 689). Throughput did not change measurably (differences are inside run-to-run noise). The cache stays because it removes allocations without costing time and does so without a validity trade-off for any definition that follows this ADR.
- A definition with a dynamic declaration layer now returns the first bake's declarations; the rules above are what protect against that.
