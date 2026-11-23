# ADR-0002: Heuristic-first generation with verified, bounded fallbacks

- Status: accepted (2026-11-19)
- References: [validators-coverage audit](../reports/validators-coverage.md), [coverage analysis](../reports/coverage-analysis.md)

## Context

The gem's identity is heuristic-first (inspired by Python's model-bakery): validators and column types drive value generation, so a plain `FactoryBakery.bake(User)` produces a valid object with zero configuration. The validators-coverage audit proved that "produces a value" is not enough — several classes of silently-invalid output existed (uniqueness collisions on second bake, presence failures on booleans and defaulted columns, regex-synthesis failures, numeric constraint breaches, proc/symbol option crashes).

## Decision

1. **Validators and column types are the primary heuristic source.** Every value-shaping validator must shape the generated value: the coverage audit's probe scenarios are permanent regression specs, and no new validator support is "done" without reproducing the audit probe.
2. **Verification over generation.** Generators may guess, but every guess is verified post-generation against the constraints; on mismatch the generator regenerates with a bounded attempt budget (aligned across uniqueness, format, numeric hygiene), and on exhaustion raises a **contextual `FactoryBakery::Error`** naming the model, attribute, and constraint — never silently returning a value known to fail validation.
3. **Dynamic options are resolved at bake time.** Proc and Symbol option values (comparison, numericality, length, inclusion/exclusion sets) are evaluated lazily against the object being built, dependency-ordered, never eagerly at filler initialization; evaluation failures surface as contextual errors preserving the cause.
4. **Optionally-true constraints relax, never lie.** `allow_nil`/`allow_blank`/conditionals only ever relax validation, so generated values may ignore them; constraint satisfaction is asserted where the constraint always applies.

## Consequences

- Deterministic-seeded and constrained value spaces surface as explicit, actionable errors instead of flaky invalid records — users are told to override via factories or relax constraints.
- A small set of shared bounded-retry budgets (10 attempts, plus wall-clock guards for regex synthesis) is a deliberate simplicity trade-off: exotic value spaces (single-value inclusion + uniqueness, unsynthesizable regexes) are expected to be handled by explicit `.define` factories, which is the intended customization mechanism.
- Regex synthesis is bounded and structure-directed, because unbounded synthesis was measured at >30s per bake on POSIX-class regexes. Since issue #65 it walks the `regexp_parser` syntax tree (`FactoryBakery::RegexGeneration`, isolated from the rest of the gem and held to 100% line and branch coverage); the earlier hand-written synthesizer and the FFaker regex path were removed.
- **Amendment (2026-11-23): the save verifies the root of a `bake!`.** Decision 2 (verification before the value is returned) holds, but where the same check is about to run anyway it is not run twice. The root record of a `bake!` whose builder needs no `valid?` verification leaves the database half of its uniqueness check to `save!`, whose unconditional uniqueness validator reports `:taken` on the attribute. `UniquenessRetry` then regenerates only attributes the gem generated, when every error on the record is such a `:taken`, up to the same ten-attempt budget, and the enforcer's own exhaustion error still ends a value space that is used up. The in-graph registry of unsaved siblings is unaffected, columns guarded only by a unique index and validators with `if:` / `unless:` / `on:` are still checked while building (a violation there would reach the database's constraint instead of a validation), and nested bakes keep checking at build time. A validated `bake!` loses half its SELECTs (4 to 2).
- The required-only rule, the exact set of nil-rejecting validators, when verification runs, and the savepoint-per-attempt fallback are recorded in [ADR-0006](0006-required-only-baking-and-verified-fallback.md).
