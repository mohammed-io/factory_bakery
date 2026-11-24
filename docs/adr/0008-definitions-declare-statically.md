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
4. **The contract is what permits caching.** With a static declaration layer, the declared pairs of a definition and of each trait can be cached per model class and per trait name and cleared when `define` is called again or code reloads, with only the per-call overrides (and the lists combined from them) rebuilt per bake. This ADR makes that contract; it does not itself add the cache. A cache layer is added only if it measurably reduces allocations or time (the project rule: a change that does not help is removed).
5. **Plugins follow the same rule.** A plugin DSL call (`association`, an attachment declaration) records a declaration while the block runs. It must also be static. Plugin declarations made inside an attribute *value* block are recorded late and stay read live; they are not a license to vary the declaration layer.
6. **Not enforced yet.** Today a dynamic declaration layer still works, because the blocks run every bake. Once a declaration cache exists, a definition that violates the contract can return a stale attribute list. The cache will therefore be keyed so that `define` replaces it, and a definition author who needs a different shape declares a trait or a second definition (a named factory) instead.

## Consequences

- The Definitions guide and the migration skill state the rule and list anti-patterns, so definitions written from now on, and ones translated from factory_bot, follow it.
- factory_bot's own factories already declare statically: attribute lists are fixed when the factory is defined, so a 1:1 translation normally satisfies the rule. Conditionals in a factory body, which factory_bot would also evaluate once at load, must be moved into value blocks or traits.
- Authors lose the ability to make a definition declare a different attribute set per environment. The replacement is a trait selected at the call site, or a value block that returns the environment-dependent value.
- Nothing changes at runtime today. The gain is the option to cache the declaration layer (roughly 20–30 fewer allocations for a definition with ten attributes, unmeasured) once that is justified by a benchmark.
