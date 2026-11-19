# ADR-0005: Condition-aware validator constraints

Accepted on 2026-11-19. This records the rule for resolving validator conditions during generation.

A validator's `if:` / `unless:` options only shape a discovered constraint when their conditions hold for the record being baked. Merging every conditional validator unconditionally produced contradictory constraint sets: complementary presence/absence guards on one attribute, or two mutually exclusive `format:` validators, collapsed into a set no value could satisfy.

The core binds the in-progress record as an opaque value around heuristic generation and the mapper reads constraints "for this record". The ActiveRecord mapper evaluates each validator's conditions after declarations, overrides, traits and `initialize_with` values are assigned and before values are generated, so a condition can read a built parent. Symbol and String method names, arity-0 Procs (evaluated in the record's context), arity-1 Procs (called with the record) and arrays of those are supported. While conditions for attribute `x` are evaluated, `x` is briefly marked changed so dirty-tracking conditions such as `will_save_change_to_x?` describe the save the generated value causes; the change is cleared afterwards. A condition that raises leaves its validator applicable, matching existing behaviour — condition evaluation never crashes a bake.

Record-specific constraints are resolved per bake and never written to the class-level constraint or filler caches, so two bakes of the same class with different parent state get the right rules each time. Unconditional reads keep the existing caches. This stays inside the ActiveRecord mapper ([ADR-0001](0001-framework-agnostic-core-mapper-plugins.md)); the Sequel mapper keeps returning unconditional constraints. `on: :create` handling is unchanged, and generated values remain verified against the applicable constraints ([ADR-0002](0002-heuristic-first-verified-generation.md)).

## Consequences

- Mutually exclusive conditional validators no longer produce unsatisfiable constraints, so real models with remote/local guards bake into valid records.
- Fillers are rebuilt per bake where a bound record is present; classes baked without one keep the existing cache path.
- A mapper that does not evaluate conditions behaves exactly as before, so adding this rule required no generator changes.
