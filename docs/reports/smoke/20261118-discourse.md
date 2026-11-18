# Smoke test — Discourse (2026-11-18)

FactoryBakery real-world smoke run against Discourse core: schema + models extracted into a
temporary SQLite harness, every selected model baked (unsaved) and validated. No app bootstrap
(no Postgres/Redis).

## Environment

| | |
|---|---|
| Gem under test | `/Users/mohammed/projects/factory_bakery` — **working tree** |
| Gem HEAD | `4fcc50784bdbf128d2fe6f9750527170db58c583` |
| Gem tree status | clean in `lib/` at run time (tested state); one untracked file `spec/factory_bakery/association_alias_group_spec.rb` from a parallel agent (untouched by this run). Post-run, parallel agents entered a merge (`bakery_builder.rb` in unmerged state) — **not** part of what was tested |
| Project clone | `discourse/discourse` @ `88fecc31b1be1b63fe4c0432325fb988adfa764c` (2026-11-18, depth 1, workspace only) |
| Ruby | 3.4.3 via `mise exec ruby@3.4.3 --` (arm64-darwin, bundler 4.0.23) |
| Workspace | `/private/var/folders/24/ghkz8rf94qj92rs78w74mnmh0000gn/T/opencode/factory_bakery-smoke/` (clone, translator, harness, `discourse.sqlite3`, `discourse_results.json`) |

Workspace-only, never-pushed Gemfile adaptations (recorded, per skill rules):

- `ruby "~> 4.0.0"` (main tracks Ruby 4) → `ruby "~> 3.4.0"` — this run is pinned to ruby 3.4.3.
- Added `gem "factory_bakery", path: "<gem checkout>"`.
- `bundle config`: `without "test development"`, `with "generic_import"` (that optional group is
  where Discourse carries `sqlite3`; all native gems installed from precompiled arm64-darwin
  binaries — pg 1.7.0, sqlite3 2.10.2, mini_racer/libv8-node, tokenizers, tiktoken).
- Bundler auto-downgraded itself 4.1.0.beta3 → 4.0.23 to match the lockfile.

Note: the `real-world-rails-smoke` skill file was updated by a parallel agent **mid-run** to a
cached deterministic pipeline. This run completed under the task brief's direct-harness
parameters; the pipeline mode is untested by this report.

## Outcome

| metric | value |
|---|---|
| Schema source | **`db/structure.sql`** (PostgreSQL dump; there is no `db/schema.rb` on main) |
| Tables created in SQLite | 403 / 403 |
| Model files (core `app/models`, plugins out of scope) | 393 |
| Models loaded (two-pass require) | **257** |
| Concrete models enumerated (non-abstract, table exists) | 240 |
| Models baked (cap **50** applied — first 50 alphabetically) | **50** |
| valid | **45** |
| invalid | **2** |
| error | **3** |
| **Pass rate** | **90.0 %** |

Per-model results (full fidelity, from `discourse_results.json`):

| model | status | signature |
|---|---|---|
| AccessControlList | valid | |
| AdminDashboardReport | error | NameError: uninitialized constant AdminDashboardReport::AdminDashboard |
| AdminDashboardSection | valid | |
| AdminNotice | valid | |
| AllowedPmUser | valid | |
| AnonymousUser | valid | |
| ApiKey | valid | |
| ApiKeyScope | valid | |
| AppearanceChange | error | NoMethodError: undefined method 'keys' for an instance of String |
| ApplicationRequest | valid | |
| AssociatedGroup | valid | |
| BackupDraftPost | valid | |
| BackupDraftTopic | valid | |
| BackupMetadata | valid | |
| Badge | valid | |
| BadgeGrouping | valid | |
| BadgeType | valid | |
| BaseTimer | error | NameError: uninitialized constant BaseTimer::Enum |
| Bookmark | valid | |
| BrowserPageviewCountryDailyRollup | valid | |
| BrowserPageviewCrawlerDailyRollup | valid | |
| BrowserPageviewEntryUrlDailyRollup | valid | |
| BrowserPageviewEvent | valid | |
| BrowserPageviewEventScore | valid | |
| BrowserPageviewReferrerDailyRollup | valid | |
| BrowserPageviewSessionEngagement | valid | |
| BrowserPageviewSessionEngagementDailyRollup | valid | |
| Category | valid | |
| CategoryActivityDailyRollup | valid | |
| CategoryCustomField | valid | |
| CategoryFeaturedTopic | valid | |
| CategoryFormTemplate | valid | |
| CategoryGroup | valid | |
| CategoryLocalization | valid | |
| CategoryModerationGroup | valid | |
| CategoryPostingReviewGroup | invalid | Category can't be blank |
| CategoryRequiredTagGroup | valid | |
| CategorySearchData | valid | |
| CategorySetting | valid | |
| CategoryTag | valid | |
| CategoryTagGroup | valid | |
| CategoryTagStat | valid | |
| CategoryUser | valid | |
| ChildTheme | valid | |
| ColorScheme | valid | |
| ColorSchemeColor | invalid | Hex is invalid |
| CustomEmoji | valid | |
| Developer | valid | |
| DirectoryColumn | valid | |
| DirectoryItem | valid | |

Highlights of what the heuristic fillers handled correctly: `Category` (name/length/slug),
`Badge`, `Bookmark`, `ApiKey` (key/token formats), `AccessControlList` (PG-array columns mapped
to text), the whole `BrowserPageview*` rollup family, `CategorySetting`, `CategoryUser`.

## Failure signatures (grouped — 5 distinct, each on 1 of 50 models)

1. **ERROR — filler eagerly evaluates a lazy Proc `:in` option** — `BaseTimer`
   `NameError: uninitialized constant BaseTimer::Enum`, gem frame `common_validators.rb:37`
   (`pick_from(values.call)` for Proc `:in`). Discourse declares
   `validates :status_type, presence/inclusion` with procs referencing `BaseTimer.types`
   (a lib-backed `Enum`); the gem calls the proc at *filler-init* time, so any proc touching app
   constants/site settings raises during bake. Gem finding: consider lazy evaluation of Proc
   `:in` (defer to `#call`, or rescue-and-skip with a recorded note).
2. **ERROR — NameError on app constants inside custom validators** — `AdminDashboardReport`
   (`#source_must_be_registered` references `AdminDashboard`). App-specific limitation: custom
   validators that depend on constants from `lib/` cannot run without a booted app. Not a gem
   defect; recorded for coverage honesty.
3. **ERROR — jsonb column fed a generic String into a Hash API** — `AppearanceChange`
   (`NoMethodError: 'keys' for String` in `#only_supported_site_settings`). Root chain: the gem
   has no json/jsonb-aware filler → string filler value assigned to the `site_settings` jsonb
   column → custom validator calls `.keys`. On real PG the same string would fail JSON parsing
   and cast to `nil`, producing the same NoMethodError — so this is a genuine **column-type gap
   (json/jsonb)**, not just a SQLite adaptation artifact.
4. **INVALID — required `belongs_to` presence with no persisted parent** — `CategoryPostingReviewGroup`
   ("Category can't be blank", "Group can't be blank"). The fillers populate FK integers but the
   targets don't exist in the disposable DB, and Rails' default belongs_to presence looks up the
   association. Unsaved-bake semantics; expected to dominate any app where required associations
   are common. Candidate gem feature: association-aware fill (create/shallow-build parents) —
   cross-reference with the bake!/persist pass design.
5. **INVALID — custom `format:` regex not satisfied** — `ColorSchemeColor` ("Hex is invalid").
   The string filler generates generic strings; validators with domain regexes (hex colors,
   hostnames, …) reject them. Validators-coverage gap: derive character-class hints from
   `format:` regexes.

## Load errors (136 / 393 files — recorded, not crashes)

Top signatures (two-pass require; singletons kept in `discourse_results.json`):

| count | signature | example file |
|---|---|---|
| 54 | `NameError: uninitialized constant Reports` | `app/models/concerns/reports/activity_by_category.rb` |
| 22 | `NameError: uninitialized constant EnumSiteSetting` | `app/models/auto_track_duration_site_setting.rb` |
| 13 | `LoadError: cannot load such file -- enum_site_setting` | `app/models/base_font_setting.rb` |
| 3 | `NameError: uninitialized constant ActiveModel::SerializerSupport` | `app/models/backup_file.rb` |
| 1 | `NameError: uninitialized constant Topic::RateLimiter` | `app/models/topic.rb` |
| 1 | `NameError: uninitialized constant Theme::GlobalPath` | `app/models/theme.rb` |

Shape of the gap: (a) `concerns/reports/*` mixins need the `Reports` namespace from `lib/` —
they are modules, not AR classes, so the bake surface is unaffected; (b) `*_site_setting.rb`
files inherit `EnumSiteSetting`, an ActiveModel (non-AR) site-setting base — again outside the
AR bake surface. The 240 enumerated concrete AR models are the real population; coverage loss is
concentrated in non-AR classes, not in bakeable models.

## Schema adaptation notes (structure.sql → SQLite)

Mechanical translator in the workspace (`discourse_translate_schema.rb`), all counts recorded:

| adaptation | count |
|---|---|
| serial `id` + separate `ALTER … SET DEFAULT nextval` → `INTEGER PRIMARY KEY AUTOINCREMENT` | 364 |
| literal defaults kept (quotes/numbers/true/false, casts stripped) | 681 |
| `jsonb`/`json` → TEXT | 75 |
| PG arrays (`bigint[]`, `text[]`, …) → TEXT | 41 |
| `inet` → VARCHAR | 15 |
| expression defaults dropped (`nextval()`, `now()`, `gen_random_uuid()`, …) | 36 |
| CHECK/UNIQUE/FK constraints dropped | 6 |
| `tsvector` → TEXT | 6 |
| `halfvec` (pgvector) / range types → TEXT | 4 |
| `uuid` → VARCHAR | 4 |
| PG enum types → VARCHAR (`ai_moderation_setting_type`, `hotlinked_media_status`) | 2 |
| `bytea` → BLOB | 1 |
| indexes, extensions (hstore, pg_trgm), functions, sequences, views | dropped wholesale (not needed for validator-driven bake) |

Zero unmapped column types, zero unparsed lines, all 403 tables created on the first SQLite
load — the dump needed no hand-editing.

## Harness corrections made during the run

- Model files are required by **absolute path**. The first run used `require "./<relative>"`,
  whose `$LOADED_FEATURES` key doesn't dedup against files' own `require_relative` calls →
  several `user_*` models executed twice, re-registering validators and flipping `ApiKey` to a
  false `invalid`. After the fix `ApiKey` validates — the doubling was corrupting results.
- pg_dump emits serial defaults via separate `ALTER TABLE … SET DEFAULT nextval` statements, so
  PK detection runs as a post-pass on the emitted DDL, not only inline.

## Cross-references to validators-coverage

- **Proc `:in` eager evaluation** (BaseTimer) → lazy-evaluation design question for fillers.
- **json/jsonb filler gap** (AppearanceChange) → new column-type filler candidate.
- **`format:` regex awareness** (ColorSchemeColor) → string filler enhancement candidate.
- **required belongs_to** (CategoryPostingReviewGroup) → association filler candidate (also
  affects the opt-in persist pass design).

## Verdict

90.0 % pass rate on the first 50 concrete Discourse models with zero schema-translation
blockers. The 5 failures are actionable and non-overlapping; none indicates a systemic filler
failure — 45/50 models pass their full validation stack on heuristic fills alone.
