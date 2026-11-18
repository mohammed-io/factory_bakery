# Real-world projects smoke test

Persistent list of open-source Rails applications used to smoke-test FactoryBakery against real models. This file is the source of truth for the `real-world-rails-smoke` skill — **add or remove projects by editing this file**; the skill reads it every run and never rewrites your choices (it only updates the `notes` and `last run` columns with what it learned).

Method: each project's schema and models are extracted into a temporary SQLite harness (no app bootstrap, no Postgres/Redis); models are baked one by one with the current working tree of the gem. Full reports land in `docs/reports/smoke/`.

Columns:

- `enabled` — `yes` to include in smoke runs, `no` to skip (kept for reference)
- `notes` — schema source (Ruby vs SQL), gem-set quirks, and blockers the skill learned
- `last run` — date + pass rate from the most recent run

| project | repo | enabled | notes | last run |
|---|---|---|---|---|
| Discourse | https://github.com/discourse/discourse | yes | SQL schema (db/structure.sql, 403 tables) — mechanical translation to SQLite works with zero hand-edits (jsonb/arrays/inet/tsvector/uuid/enums mapped; indexes+FKs dropped). Main pins ruby ~> 4.0 — workspace Gemfile edit to 3.4 needed for the 3.4.3 run. 257/393 core model files load standalone (reports-concern mixins + non-AR EnumSiteSetting classes don't — both outside AR bake surface). 2026-11-18: 90.0 % (45/2/3 of 50); failures: Proc-`:in` eager eval, jsonb filler gap, format-regex gap, required belongs_to, app-constant validators | 2026-11-18 90.0 % |
| Mastodon | https://github.com/mastodon/mastodon | yes | Ruby schema (db/schema.rb), 122 tables — loads mechanically on SQLite after in-script adaptations (jsonb/uuid/inet/citext mapped; array options+defaults, lambda `timestamp_id` PK defaults, expression/NULLS-indexes, PG extensions, scenic materialized views dropped). Heavy gem set installs cleanly on Rails 8.1 with 2 cached skips (puma, tzinfo-data — template-Gemfile conflicts); no lockfile drift. Extract lib/ too: upstream keeps `Mastodon::`, Chewy patches, Vite helpers in `lib/` (boot-required — pipeline copies to `upstream_lib/` + LOAD_PATH). 313 files → 263 load standalone (50 load errors: CLI/`pastel` noise 17, missing app/services tree ~25, asset/i18n ENOENT 3). 2026-11-18: 10.0 % (5/34/10/1 of 50 distinct) — 29 invalids are one required-`belongs_to` signature (association-dense app); other findings: filler trusts blank DB defaults over presence (4 models), PG-array column fed String (CustomFilter), FeaturedTag bake spins >20 s under new uniqueness path. First full run of the deterministic pipeline — 12 script bugs fixed (see report); cache valid | 2026-11-18 core 10.0 % → plugin 18.0 % → post-V2 28.0 % (~93 % bakeable) |
| GitLab | https://github.com/gitlabhq/gitlab | yes | SQL schema (structure.sql) — extraction + translation required; enormous model count, cap applies | never |
| Forem | https://github.com/forem/forem | yes | Large model surface; well-structured app/models | never |
| Decidim | https://github.com/decidim/decidim | yes | Engine-based: host app models primary, engine models optional extras | never |
| Spree | https://github.com/spree/spree | yes | Engine-based e-commerce; classic AR models with rich validations | never |
| OpenProject | https://github.com/OpenProject/OpenProject | no | SQL schema likely; enable manually | never |
| Redmine | https://github.com/redmine/redmine | no | Older Rails conventions; enable manually | never |
| Zammad | https://github.com/zammad/zammad | no | Large gem set; enable manually | never |
