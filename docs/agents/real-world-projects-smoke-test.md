# Real-world projects smoke test

Persistent list of open-source Rails applications used to smoke-test FactoryBakery against real models. This file is the source of truth for the `real-world-rails-smoke` skill — **add or remove projects by editing this file**; the skill reads it every run and never rewrites your choices (it only updates the `notes` and `last run` columns with what it learned).

Columns:

- `enabled` — `yes` to include in smoke runs, `no` to skip (kept for reference)
- `setup notes` — what the skill (or you) learned about bootstrapping this project locally; blockers live here
- `last run` — date + pass rate from the most recent run; full reports in `docs/reports/smoke/`

| project | repo | enabled | setup notes | last run |
|---|---|---|---|---|
| Discourse | https://github.com/discourse/discourse | yes | Postgres + Redis; `bin/discourse-setup` or d/dev.rb; well-documented dev bootstrap | never |
| Mastodon | https://github.com/mastodon/mastodon | yes | Postgres + Redis; needs env vars from `.env.production` sample; Rails app in root | never |
| GitLab | https://github.com/gitlabhq/gitlab | yes | Very heavy setup (Gitaly, Workhorse); expect the 15-minute rule to bite; smoke via `rails runner` against a test DB if achievable | never |
| Forem | https://github.com/forem/forem | yes | Postgres + Redis; `bin/setup`; large model surface | never |
| Decidim | https://github.com/decidim/decidim | yes | Rails engines; `develop_app` generated per docs; rich validations | never |
| Spree | https://github.com/spree/spree | yes | E-commerce; sandbox app via `sandbox` script; classic AR models | never |
| OpenProject | https://github.com/OpenProject/OpenProject | no | Postgres; heavy; enable manually | never |
| Redmine | https://github.com/redmine/redmine | no | Older Rails conventions; MySQL/Postgres; enable manually | never |
| Zammad | https://github.com/zammad/zammad | no | Postgres + Elasticsearch + Redis; enable manually | never |
