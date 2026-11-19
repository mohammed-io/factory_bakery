# ADR-0003: Associations as an opt-in plugin with bounded modes

- Status: accepted (2026-11-19)
- References: [associations design](../associations-design.md), associations epic issues A1–A20 (#11–#30)

## Context

Building associated records is the highest-value and highest-risk capability: naive recursion cycles, fan-out explodes graphs, persistence ordering breaks foreign keys, and real apps validate raw FK columns or maintain counter caches. The v0.0.2 core shipped with associations deliberately deferred.

## Decision

1. **Opt-in plugin.** `require 'factory_bakery/associations'` (or `config.factory_bakery.associations` in Rails). Core raises a contextual error when the reserved `association` DSL name is used without the plugin. The plugin sits on the core plugin-hook seam (DSL declarations, heuristic contributions, post-instantiate hooks) and the mapper contract's association introspection — it contains no value-synthesis logic.
2. **Guard-rails first in core.** STI discriminators, belongs_to foreign keys, polymorphic pairs, and counter-cache columns are never randomly filled — with or without the plugin — because fabricated values dangle against real constraints.
3. **Bounded modes.** `:none` (explicit only), `:required_only` (auto-build required `belongs_to`; reflection-path cycle detection raising `CyclicAssociationError`; unsaved parents under `bake`), `:all` (adds optional parents and collections with depth truncation to required-only and no back-edges). Defaults are conservative; `Associations.with(mode:, max_depth:, default_count:)` scopes overrides fiber-locally.
4. **Persistence is atomic and verified.** `bake!` wraps the graph in a savepoint transaction and raises `IncompletePersistenceError` if any generated record remains unsaved; parents required by raw-FK-presence validation are persisted inside the same savepoint.
5. **Strategies are explicit.** `strategy: :fresh | :reuse` (`:reuse` = same-bake graph match, else oldest DB row; belongs_to-only; no traits), with in-graph diamond dedup.

## Consequences

- The gem's default path stays zero-configuration and insert-free; association building is a deliberate upgrade that cannot surprise users who never loaded it.
- Real-app smoke runs (Mastodon/Discourse) measured the required-belongs_to class as the single largest invalid mass — this epic is the direct answer to that measurement.
- Sequel association building is intentionally absent (future mapper work); Sequel edges are guarded (FKs left nil), never mis-built.
- Transients, callbacks, and sequences remain deferred; the plugin hook seam is the designed landing point for them.
