# ADR-0001: Framework-agnostic core with ORM mapper plugins

- Status: accepted (2026-11-19)
- Decision makers: Mohammed A. (owner), orchestration agent (proposal)
- References: [coverage-analysis.md](../reports/coverage-analysis.md), architecture guard spec (`spec/factory_bakery/architecture_guard_spec.rb`)

## Context

FactoryBakery generates fake model data by reading a target model's schema and validators. The original implementation let that reading leak everywhere: filler classes matched validator class-name strings, the builder walked `columns_hash` and `defined_enums`, `bake!` called `ActiveRecord::Base.transaction` directly, and the Railtie pulled `rails` into the require graph. Supporting a second ORM (Sequel) under that design would have meant duplicating framework reads in every generator, and the "100% of real-world use cases" goal required being able to add new ORM integrations without touching value-synthesis logic.

A full audit plus two real-app smoke runs (Mastodon, Discourse) confirmed the split: value synthesis is universal (given constraints, produce a plausible value), while constraint *discovery* is entirely framework-specific.

## Decision

The gem is split into a **framework-agnostic core** and **mapper plugins**:

1. **Core** (loaded by `require 'factory_bakery'`) contains: the public API (`FactoryBakery.define/bake/bake!/find_definitions`, `Methods`), pure value generators that consume a normalized `ConstraintSet` (lengths, regexes, sets, numeric bounds + parity, enum values, format verification rules), the builder machinery (winning declarations, alias groups as data, bake-time lazy resolution, depth backstop, generated-record tracking), the definition loader, the plugin registry, and duck-typed persistence. The core references **no** `ActiveRecord`, `ActiveModel`, `Rails`, or `ActiveSupport` constant and requires none of those gems.
2. **Mapper plugins** implement a registry contract — `supported?`, `attribute_universe`, `constraints_for` (→ `ConstraintSet`), `guard_columns`, `alias_groups`, `association_introspection`, `uniqueness_check`, persistence adapter (transaction-with-savepoint, `save!`, `persisted?`). The **ActiveRecord mapper is shipped and auto-registered when ActiveRecord is available** (default behavior identical to the pre-refactor gem); the **Sequel mapper is opt-in** (`require 'factory_bakery/sequel'`, optional dependency, never in the gemspec). Multiple mappers may be registered; first supported wins.
3. **The boundary is enforced by an architecture guard spec** that fails the suite if any core file references a framework constant or requires a framework gem — including an armed canary (proving the check catches real references) and a framework-free subprocess proof (the gem loads and bakes a PORO with Rails provably never loaded).

## Consequences

- Adding an ORM means writing one mapper plugin; no generator or core changes. Sequel support shipped this way without touching a single generator.
- The core can be tested (and used) in complete isolation from Rails — proven by the subprocess example.
- Rails-specific behavior (Railtie definition auto-loading, `config.factory_bakery.associations`, autosave semantics, savepoint transactions) lives in the AR mapper plugin. Applications not using Rails get core + mappers only.
- Migration cost: every validator-reading change now lands in the AR mapper's constraint reader; the generators change only when the *value* semantics change. The guard spec makes silent regressions impossible.
- Known accepted residue: `TimeWithZone`/`Duration`-style arithmetic was replaced with stdlib-only temporal arithmetic proven byte-identical (Marshal comparison across DST/timezones), so even date math does not silently depend on ActiveSupport.
