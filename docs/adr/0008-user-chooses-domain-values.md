# ADR-0008: The user chooses domain values

- Status: accepted (2026-11-23)
- References: [Discourse smoke definitions](../reports/smoke/20261119-final-discourse-definitions.rb), [ADR-0004](0004-extend-generation-within-discoverable-constraints.md)

## Context

After automatic handling, Discourse still needs 40 definitions for its 413 models and Mastodon 32 for its 123. Several fail only because a custom validator rejects the generated enum, inclusion, boolean, or STI type value. For example, Discourse `WebHook` needs `wildcard_web_hook = true` without seeded event types, `AdPlugin::AdImpression` needs a nil house-ad id for a non-house `ad_type`, and `Reviewable#type` needs a concrete STI subclass. A gem could search candidate values until `valid?` passes.

## Decision

1. When a custom validator rejects a generated value, FactoryBakery does not search other enum values, inclusion members, booleans, or STI subclasses for one that passes.
2. Which value to use is a domain decision with meaning: `wildcard_web_hook = true` changes what the webhook does; `ad_type: :adsense` versus `:house` changes behavior; tests could silently depend on a value the gem picked. The user declares it in a definition.
3. Help instead of guessing: `bake!`'s error and `FactoryBakery.explain(record)` print a copy-pasteable definition snippet naming the attribute.
4. What the gem resolves automatically stays structural, not semantic: a subclass without a definition uses its nearest ancestor's; a `belongs_to` with a missing class constant resolves through the database foreign key; a polymorphic `belongs_to` is narrowed by a database foreign key on its id column; `*_remote_url` attributes are left blank with a WARN log.

## Consequences

- Discourse keeps 40 definitions and Mastodon 32 by design. The roughly 80% automatic target is still met: about 90% of models bake valid with no definitions at all.
- Bakes stay predictable: a value either comes from discoverable constraints or from the user. Runs are reproducible with `FactoryBakery.seed`.

## Alternatives considered

**Bounded value search over rejected attributes.** This would have removed about 5–8 Discourse definitions: `AdImpression`, `WebHook`, `SkippedEmailLog`, `Permalink`, `CompletionPrompt`, `Reviewable`, and `Chat::Channel`. Rejected because these choices carry domain meaning and searching adds extra `valid?` calls.

**Auto-persisting parents after an invalid rebuild.** Rejected because plain `bake` would write hidden rows. `association :x, persist: true` stays explicit and is one line.

**Dropping invalid optional associations in `:all` mode.** Rejected because `:all` would silently mean “not all”; `skip :x` stays explicit.
