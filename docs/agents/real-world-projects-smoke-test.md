# Real-world projects smoke test

Persistent list of open-source Rails applications used to smoke-test FactoryBakery against real models. This file is the source of truth for the `real-world-rails-smoke` skill — **add or remove projects by editing this file**; the skill reads it every run and never rewrites your choices (it only updates the `notes` and `last run` columns with what it learned).

Method: each project's schema and models are extracted into a temporary SQLite harness (no app bootstrap, no Postgres/Redis); models are baked one by one with the current working tree of the gem. Full reports land in `docs/reports/smoke/`.

Columns:

- `enabled` — `yes` to include in smoke runs, `no` to skip (kept for reference)
- `notes` — schema source (Ruby vs SQL), gem-set quirks, and blockers the skill learned
- `last run` — date + pass rate from the most recent run

| project | repo | enabled | notes | last run |
|---|---|---|---|---|
| Discourse | https://github.com/discourse/discourse | yes | Verify schema format on clone; plugin/engine models out of scope | never |
| Mastodon | https://github.com/mastodon/mastodon | yes | Verify schema format on clone; heavy gem set — expect a couple of load-error findings | never |
| GitLab | https://github.com/gitlabhq/gitlab | yes | SQL schema (structure.sql) — extraction + translation required; enormous model count, cap applies | never |
| Forem | https://github.com/forem/forem | yes | Large model surface; well-structured app/models | never |
| Decidim | https://github.com/decidim/decidim | yes | Engine-based: host app models primary, engine models optional extras | never |
| Spree | https://github.com/spree/spree | yes | Engine-based e-commerce; classic AR models with rich validations | never |
| OpenProject | https://github.com/OpenProject/OpenProject | no | SQL schema likely; enable manually | never |
| Redmine | https://github.com/redmine/redmine | no | Older Rails conventions; enable manually | never |
| Zammad | https://github.com/zammad/zammad | no | Large gem set; enable manually | never |
