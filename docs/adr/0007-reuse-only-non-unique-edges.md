# ADR-0007: `:reuse_non_unique` — reuse a parent only where uniqueness allows it

- Status: accepted (2026-11-20)
- Amends: [ADR-0003](0003-associations-opt-in-plugin-bounded-modes.md) decision 5 (strategies)
- References: [Mastodon smoke report](../reports/smoke/20261120-fixes-mastodon.md), [Discourse smoke report](../reports/smoke/20261120-fixes-discourse.md)

## Context

ADR-0003 introduced `strategy: :fresh | :reuse`. `:reuse` hands a `belongs_to` the first completed object of the target class in the same bake, otherwise the oldest matching database row. It never asked whether the edge allows two owners to share one parent.

The real-app smoke runs showed that it often doesn't:

- Mastodon `Appeal belongs_to :account_warning`, with a unique index on `appeals.account_warning_id`. Reuse picked a warning that was already appealed, so the bake failed with "Account warning has already been taken".
- Discourse `UserProfileView`, `UserPassword` and similar models: reuse picked a user that already had the one-per-user row, so the bake hit a duplicate key or "User has already been taken".

Each failure depends on what happens to be in the database, so `:reuse` results changed from run to run. The point of `:reuse` is to share lookup-style parents (a category, an account, a site), never a parent that can belong to only one owner.

## Decision

1. **The strategy is renamed `:reuse_non_unique`.** The name states the rule. `:reuse` is removed with no alias, because the gem is unreleased; passing it raises the usual invalid-strategy `ArgumentError`.
2. **Reuse only where the edge has no uniqueness.** A `belongs_to` edge counts as unique when any of these holds, and then it builds a fresh parent exactly as `:fresh` would:
   - a unique index on the owner's table includes any of the edge's foreign key columns, single or composite (any uniqueness counts, scope or not);
   - the owner validates uniqueness of the foreign key attribute or of the association;
   - the target's inverse of the edge is a `has_one`, so one parent has at most one owner by design.
3. **A unique edge never touches the reuse cache.** It skips the in-graph lookup and the database lookup. The fresh parent it builds is not remembered for reuse, so a later edge can't share it either.
4. **Everything else is unchanged.** Non-unique edges behave as `:reuse` did: in-graph match first, then the oldest matching row by primary key, otherwise a fresh build. The strategy still applies to `belongs_to` only, and traits are still refused. Precedence is still per-association, then `Associations.with(strategy:)`, then the global setting.
5. **Uniqueness is read through the mapper.** Index and validator facts come from the mapper's introspection, so the core stays framework-agnostic ([ADR-0001](0001-framework-agnostic-core-mapper-plugins.md)).

## Consequences

- With `:reuse_non_unique`, a bake no longer fails because of rows already in the database. The `:reuse` failures in the smoke runs that came from picking an already-taken parent go away by construction, not by luck.
- Graphs with unique edges create more rows than `:reuse` did. That is the intended trade: correctness over sharing.
- "Unique" is decided conservatively. A composite unique index such as `[user_id, topic_id]` also forces a fresh `user`, even though sharing would be fine when the topic differs. Deciding that per row would mean querying the other columns, which this ADR deliberately avoids (YAGNI). A user who wants sharing there can still pass the parent explicitly or declare the association.
- Uniqueness enforced only in application code that the mapper can't see (custom validators, callbacks) is not detected; such edges are still reused and need a declaration.
