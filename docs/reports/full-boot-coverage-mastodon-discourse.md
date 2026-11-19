# Full-boot coverage — Mastodon & Discourse (2026-11-19)

**Definitive real-world validation of FactoryBakery.** Both applications were cloned whole,
provisioned with real sidecars (Postgres + Redis), given their **real schema**, booted through
their **own Rails boot**, and baked inside that genuine process. No harness, no schema
adaptation, no stubbing of app files.

| | |
|---|---|
| Gem under test | `/Users/mohammed/projects/factory_bakery` working tree |
| Gem HEAD | `2c27ed4bc97e819bead3cdc22c089dcd1583553d` |
| Ruby | `3.4.3` via `mise exec ruby@3.4.3 --` |
| Runner | `/Users/mohammed/.agents/skills/real-world-rails-smoke/scripts/real_app_smoke.rb` (full-boot pipeline) |
| Cache | `.smoke-tests/real-app-cache/{discourse,mastodon}/` (full clones + `BOOT-READY` + `last-run.jsonl`) |
| Sidecars | `fb_probe_pg` (Postgres 16, `127.0.0.1:55432`, `postgres`/`postgres`), `fb-smoke-redis` (Redis 7, `localhost:56379`); MySQL `fb_probe_my` was up but unused |
| Model set | 50 distinct, table-backed, non-abstract AR descendants, sorted by class name, cap 50 |
| Passes | A `required_only`/`fresh`, B `required_only`/`reuse`, C `all`/`fresh`, D `all`/`reuse` |
| Bake semantics | unsaved `bake`, `valid?(:create) || valid?`, per-model 20 s timeout |

---

## 1. Boot notes

### Mastodon — ✅ BOOTED

| item | value |
|---|---|
| Upstream | `166fb24fa53c13f632513f2aafc42f4f0cdb50b2` (full clone, 10,128 files) |
| Ruby friction | Upstream now pins `.ruby-version 4.0.10` and `ruby file: '.ruby-version'`. Set the clone's `.ruby-version` to `3.4.3` (clone-local only). |
| Gem injection | Appended `gem 'factory_bakery', path: '<gem root>'` to the clone Gemfile. |
| Bundle | `bundle install --jobs 4` — 156 deps / 346 gems, clean (no lockfile drift). |
| DB | `RAILS_ENV=development DB_HOST=127.0.0.1 DB_PORT=55432 DB_USER=postgres DB_PASS=postgres REDIS_URL=redis://localhost:56379/0 rails db:create db:schema:load` — real `db/schema.rb`, 122 tables + snowflake ID sequences. |
| Gotcha | `DB_HOST=localhost` resolves to `::1` and fails `fe_sendauth`; use `127.0.0.1`. |
| Boot check | `rails runner 'require "factory_bakery/associations"; Rails.application.eager_load!'` → Rails 8.1.4.1, FactoryBakery 0.0.2.0, **125 AR descendants**. |

### Discourse — ✅ BOOTED

| item | value |
|---|---|
| Upstream | `58f5edd2b7ebd05f0e6540c5e4c7aee6a9134b86` (full clone, 28,236 files) |
| Ruby friction | Upstream Gemfile pins `ruby "~> 4.0.0"`. Changed to `3.4.3` in the clone only. |
| Gem injection | Appended `gem 'factory_bakery', path: '<gem root>'` to the clone Gemfile. |
| Bundle | `bundle install --jobs 4` — 171 deps / 287 gems, clean. |
| DB | `rake db:create` created `discourse_development` + `discourse_test`. `db:migrate` aborts because `node_modules` is missing (asset precompile), so the app's **real `db/structure.sql`** was loaded directly with `docker exec -i fb_probe_pg psql -U postgres -d discourse_development < db/structure.sql` — **402 tables, zero adaptation**. |
| JS friction | Baking models with text columns invokes Discourse's pretty-text JS bundle. Installed `pnpm@12.11.2` via corepack and ran `pnpm install --frozen-lockfile` (703 MB `node_modules`) in the clone. |
| DB connection | libpq env vars `PGHOST=127.0.0.1 PGPORT=55432 PGUSER=postgres PGPASSWORD=postgres`; Redis via `DISCOURSE_REDIS_HOST/PORT`. |
| Boot check | `rails runner 'require "factory_bakery/associations"; Rails.application.eager_load!'` → Rails 8.1.4.1, FactoryBakery 0.0.2.0, **418 AR descendants**. `rails runner` needs no asset precompile once node_modules exist. |

### Script fixes made during this run (all in the skill script, reported as required)

1. **`options` NameError** — `bootstrap!` referenced a top-level local; promoted to `OPTIONS` constant after `OptionParser`.
2. **`Open3.capture2e(..., chdir: nil)` TypeError** (Ruby 3.4.3) — only pass `chdir:` when non-nil.
3. **`String#shellescape` NoMethodError** — added `require "shellwords"`.
4. **`rails runner /dev/stdin` silently executed nothing** (Rails 8 + bundler re-exec loses stdin) — the runner is now written to a real `<project>/runner.rb` and passed by path.
5. **Runner hardening** (the owner's matrix): single-boot runner now runs all four `Associations.with(mode:, strategy:)` passes, eager-loads the real app through Zeitwerk, optionally `require`s a real definitions `.rb` file, restricts to named models for re-bakes, stamps every JSON line with its pass label, and excludes `ActiveRecord::*` internal descendants.
6. Added `--passes`, `--output`, `--definitions`, `--only`, `--skip-pull` CLI knobs.

---

## 2. Mastodon

### 2.1 Four-pass outcome table (50 models)

`V` = valid, `I` = invalid (+errors), `E` = error (+exception), `T` = timeout. The last column is
the pass-A re-bake **with the custom factories from §2.4 loaded**.

| model | A req/fresh | B req/reuse | C all/fresh | D all/reuse | after define |
|---|---|---|---|---|---|
| Account | error | error | error | error | valid |
| AccountAlias | error | error | error | error | error |
| AccountConversation | error | error | error | error | valid |
| AccountDeletionRequest | error | error | error | error | valid |
| AccountDomainBlock | valid | error | error | error | valid |
| AccountMigration | error | error | error | error | invalid |
| AccountModerationNote | error | error | error | error | valid |
| AccountNote | error | valid | error | error | valid |
| AccountPin | error | error | error | error | invalid |
| AccountReachFilter | valid | error | error | error | valid |
| AccountRelationshipSeveranceEvent | error | error | error | error | valid |
| AccountStat | error | error | error | error | valid |
| AccountStatusesCleanupPolicy | error | error | error | error | valid |
| AccountSummary | error | error | error | error | valid |
| AccountWarning | error | error | error | error | valid |
| AccountWarningPreset | valid | valid | valid | valid | valid |
| Admin::ActionLog | error | error | error | error | valid |
| Admin::ServerCheck | valid | valid | valid | valid | valid |
| Announcement | valid | valid | error | invalid | valid |
| AnnouncementMute | error | error | error | error | valid |
| AnnouncementReaction | error | error | error | error | valid |
| Appeal | error | invalid | error | error | valid |
| Backup | error | error | error | error | valid |
| Block | error | valid | error | error | valid |
| Bookmark | error | error | error | error | valid |
| BulkImport | error | error | error | error | valid |
| BulkImportRow | valid | error | valid | error | valid |
| CanonicalEmailBlock | valid | valid | error | error | valid |
| Collection | error | error | error | error | error |
| CollectionItem | error | error | error | error | valid |
| CollectionReport | error | error | error | error | valid |
| Conversation | valid | valid | error | error | valid |
| ConversationMute | error | error | error | error | valid |
| CustomEmoji | invalid | invalid | invalid | invalid | valid |
| CustomEmojiCategory | valid | valid | invalid | invalid | valid |
| CustomFilter | error | error | error | error | valid |
| CustomFilterKeyword | error | error | error | valid | valid |
| CustomFilterStatus | error | error | error | error | invalid |
| DomainAllow | valid | valid | timeout | timeout | valid |
| DomainBlock | valid | valid | timeout | timeout | valid |
| Doorkeeper::AccessGrant | error | error | error | error | valid |
| Doorkeeper::AccessToken | valid | valid | error | error | valid |
| Doorkeeper::Application | error | error | error | error | valid |
| EmailDomainBlock | valid | valid | error | error | valid |
| EmailSubscription | error | error | error | error | valid |
| Fasp::BackfillRequest | valid | valid | valid | valid | valid |
| Fasp::Capability | valid | valid | valid | valid | valid |
| Fasp::DebugCallback | valid | valid | valid | valid | valid |
| Fasp::FollowRecommendation | error | error | error | error | valid |
| Fasp::Provider | valid | valid | valid | valid | valid |

**Pass totals:** A **17 valid / 1 invalid / 32 error / 0 timeout (34.0 %)** · B **16/2/32/0 (32.0 %)** ·
C **7/2/39/2 (14.0 %)** · D **7/3/38/2 (14.0 %)**.

### 2.2 Four-pass comparison — which knob rescued which model

- **Valid in all four (6):** `AccountWarningPreset`, `Admin::ServerCheck`, `Fasp::BackfillRequest`,
  `Fasp::Capability`, `Fasp::DebugCallback`, `Fasp::Provider`.
- **`:required_only`/`:reuse` (B) rescued** `AccountNote` and `Block` (both `error` under A → `valid` under B) —
  reusing an existing parent avoided the fresh-parent build that failed.
- **`:all`/`:reuse` (D) rescued** `CustomFilterKeyword` (error under A/B/C → valid under D).
- **`:all` is a net regression here.** No model became valid under C that was not already valid under A.
  It *broke* 12 models that passed A, because auto-building has_many/has_one children triggers more
  remote-avatar HTTP fetches and strict FK-under-`:fresh` errors. `DomainAllow`/`DomainBlock` went
  from valid (A/B) to **timeout** (C/D). `Announcement`, `CustomEmojiCategory`,
  `Doorkeeper::AccessToken`, `EmailDomainBlock`, `CanonicalEmailBlock`, `Conversation` etc. regressed.
- **Pass A is the best knob** for this app (34 %); switching strategy alone gains at most +2 models,
  switching mode to `:all` loses 10.

**Dominant real-app failure signature (A):** 32 errors, of which 26 are
`HTTP::ConnectionError`/`SSL`/`TooManyRedirects`/`403` from `Account#avatar_remote_url=` performing a
**live HTTP fetch** (`app/models/concerns/remotable.rb:30`) against a fake generated domain — a genuine
app-inherent side effect the harness could never surface. 5 are the `Account#username` combined-regex
synthesis gap; 1 is the required polymorphic `Doorkeeper::Application#owner`.

### 2.3 Out-of-box (pass A valid) — plain list

17 models: `AccountDomainBlock`, `AccountReachFilter`, `AccountWarningPreset`, `Admin::ServerCheck`,
`Announcement`, `BulkImportRow`, `CanonicalEmailBlock`, `Conversation`, `CustomEmojiCategory`,
`DomainAllow`, `DomainBlock`, `Doorkeeper::AccessToken`, `EmailDomainBlock`, `Fasp::BackfillRequest`,
`Fasp::Capability`, `Fasp::DebugCallback`, `Fasp::Provider`.

### 2.4 Needs define — 28 models, working custom factories

Real file: `.smoke-tests/real-app-cache/mastodon/app/smoke_definitions.rb`, `require`-loaded by the
runner via `SMOKE_DEFINITIONS`. Loading these + re-baking pass A lifted **17 → 45 valid (90 %)**,
i.e. **28 rescued**. Key snippets:

```ruby
FactoryBakery.define(Account) do
  avatar_remote_url { nil }         # kills the live remote-avatar HTTP fetch
  header_remote_url { '' }          # NOT NULL default '' in db/schema.rb
  avatar { nil }; header { nil }
  domain { nil }; uri { nil }       # local accounts skip remote uri/inbox rules
  inbox_url { '' }; outbox_url { '' }
  followers_url { '' }; following_url { '' }; shared_inbox_url { '' }
  username { "fb_#{SecureRandom.hex(5)}" } # two regexes defeat the synthesizer
end

FactoryBakery.define(User) do
  email { "fb_#{SecureRandom.hex(5)}@example.com" } # User#email regex synthesis gap
  password { 'SmokePass123!' }
  agreement { true }
end

FactoryBakery.define(Doorkeeper::Application) do
  owner_id { nil }; owner_type { nil }
  owner { FactoryBakery.bake!(User) } # polymorphic owner has a real FK to users
  redirect_uri { 'https://example.com/callback' }
end

FactoryBakery.define(Status)       { text { 'smoke status text' } }
FactoryBakery.define(Backup)       { dump { nil } }
FactoryBakery.define(EmailDomainBlock) { parent { nil } }     # self-referential cycle
FactoryBakery.define(CustomEmoji) do
  image_file_name { 'emoji.png' }; image_content_type { 'image/png' }; image_file_size { 1024 }
end
FactoryBakery.define(AnnouncementReaction) { name { '🐮' } } # emoji_map.json key
FactoryBakery.define(CustomFilter) { title { 'smoke filter' }; context { ['home'] } }
FactoryBakery.define(AccountWarning) { created_at { Time.current } } # appeal window
```

Rescued models: `Account`, `AccountConversation`, `AccountDeletionRequest`, `AccountModerationNote`,
`AccountNote`, `AccountRelationshipSeveranceEvent`, `AccountStat`, `AccountStatusesCleanupPolicy`,
`AccountSummary`, `AccountWarning`, `Admin::ActionLog`, `AnnouncementMute`, `AnnouncementReaction`,
`Appeal`, `Backup`, `Block`, `Bookmark`, `BulkImport`, `CollectionItem`, `CollectionReport`,
`ConversationMute`, `CustomEmoji`, `CustomFilter`, `CustomFilterKeyword`, `Doorkeeper::AccessGrant`,
`Doorkeeper::Application`, `EmailSubscription`, `Fasp::FollowRecommendation`.

### 2.5 Still failing — 5 models, diagnosis

| model | status | diagnosis |
|---|---|---|
| `AccountPin` | invalid | **App-inherent.** `validate_follow_relationship` requires a persisted `Follow` (`account.following?(target_account)`); an unsaved bake has no follow rows. No attribute define can satisfy it without persisting a coordinated account+follow graph. |
| `AccountMigration` | invalid | **App-inherent.** A define was attempted (persist owner, build `target_account` with correct `also_known_as`); it got the target in place but `validates :acct, domain: { acct: true }` needs a *persisted, resolvable* account for the `acct` string and `validate_migration_cooldown` queries persisted migrations. Requires full-boot DB state. |
| `CustomFilterStatus` | invalid | **App-inherent.** `validate_status_access` calls `StatusPolicy.new(custom_filter_account, status).show?` (Pundit); unsaved objects fail the visibility policy. The nested `Status` itself validates fine — only the policy lookup fails. |
| `AccountAlias` | error | **App-inherent.** `set_uri`/`validate_target_account` call `ResolveAccountService` and `TagManager.uri_for(account)`; with an unsaved account `uri_for` generates `ap_account_url(nil)` → `ActionController::UrlGenerationError`. Needs a persisted, resolvable remote account. |
| `Collection` | error | **Order/state-sensitive.** Passed in an isolated re-bake with the final defines; failed in the full 50-run after earlier defines committed rows via `bake!` (`NoMethodError: undefined method 'role' for nil` at `app/models/collection.rb:121`), i.e. a DB-state collision from persisted fixtures, not a stable filler gap. |

**Gem gaps exposed by Mastodon (name + sketch):**
1. `Account#username` has two overlapping format regexes (remote `/\A[a-z0-9_]+([.-]+[a-z0-9_]+)*\z/i` and
   local `/\A[a-z0-9_]+\z/i`); `RegexSynthesizer` tries to satisfy both simultaneously and fails in 10 attempts.
   Sketch: intersect conjunctive regexes before synthesis, or prefer the more restrictive literal form.
2. `User#email` regex `/\A[^@\s]+@[^@\s]+\z/` with `maximum: 320` produced `" \t\t @\t^@"` on 10 attempts.
   Sketch: seed the email filler from a valid local@domain template when a format validator is present.
3. `belongs_to_required_by_default` + `has_attached_file` NOT NULL defaults: heuristics hand `nil` to
   NOT NULL columns (`header_remote_url`, `inbox_url`) when a define clears a remote URL. Sketch:
   consult column nullability/defaults before assigning a define-provided `nil`.

### 2.6 Does `.define` handle 100 % of Mastodon? — **No.**

Out-of-box **34 %** → with `.define` **90 %**. Residue: 5 models (3 genuinely app-inherent needing
persisted state/policies, 1 persisted-account URI generation, 1 order-dependent DB-state collision).
`.define` is a strong escape hatch but cannot manufacture full-boot runtime state.

---

## 3. Discourse

### 3.1 Four-pass outcome table (50 models)

| model | A req/fresh | B req/reuse | C all/fresh | D all/reuse | after define |
|---|---|---|---|---|---|
| AccessControlList | error | error | error | error | valid |
| AdPlugin::AdImpression | invalid | invalid | error | error | valid |
| AdPlugin::HouseAd | valid | valid | valid | invalid | valid |
| AdPlugin::HouseAdRoute | valid | valid | valid | valid | valid |
| AdminDashboardReport | invalid | invalid | invalid | invalid | invalid |
| AdminDashboardSection | valid | valid | valid | valid | valid |
| AdminNotice | valid | valid | valid | valid | valid |
| AiAgent | invalid | invalid | error | error | valid |
| AiAgentMcpServer | error | error | error | error | valid |
| AiApiAuditLog | valid | valid | error | error | valid |
| AiApiRequestStat | valid | valid | valid | valid | valid |
| AiArtifact | error | error | error | error | valid |
| AiArtifactKeyValue | error | error | error | error | valid |
| AiArtifactShare | error | error | error | error | valid |
| AiArtifactShareKeyValue | error | error | error | error | valid |
| AiArtifactVersion | error | error | error | error | error |
| AiMcpOauthToken | valid | valid | error | error | valid |
| AiMcpServer | invalid | invalid | error | error | valid |
| AiModerationSetting | invalid | invalid | error | error | invalid |
| AiPostImageCaption | error | error | error | error | valid |
| AiReviewableSuggestion | error | error | error | error | valid |
| AiSecret | valid | valid | error | error | valid |
| AiSpamLog | error | error | error | error | valid |
| AiSummary | error | error | error | error | valid |
| AiTool | error | error | error | error | valid |
| AiToolAction | valid | valid | error | error | valid |
| AiToolSecretBinding | error | error | error | error | invalid |
| AllowedPmUser | valid | valid | error | error | valid |
| AnonymousUser | valid | valid | error | error | valid |
| ApiKey | valid | valid | error | error | invalid |
| ApiKeyScope | valid | valid | valid | valid | valid |
| AppearanceChange | valid | valid | error | error | valid |
| ApplicationRequest | valid | valid | valid | valid | valid |
| AskAiLog | valid | valid | error | error | valid |
| AskAiReport | valid | valid | error | error | valid |
| AskAiReportSubject | valid | valid | error | error | valid |
| AskAiReportSubjectAsk | valid | valid | valid | valid | valid |
| Assignment | error | error | error | error | error |
| AssociatedGroup | valid | valid | valid | valid | valid |
| BackupDraftPost | error | error | error | error | valid |
| BackupDraftTopic | error | error | error | error | valid |
| BackupMetadata | valid | valid | valid | valid | valid |
| Badge | valid | valid | error | error | valid |
| BadgeGrouping | valid | valid | error | error | valid |
| BadgeType | valid | valid | error | error | valid |
| BaseTimer | valid | valid | error | error | valid |
| Blog::Path | error | error | error | error | error |
| Blog::Publication | error | error | error | error | valid |
| Blog::Review | error | error | error | error | valid |
| Blog::ReviewFeedback | error | error | error | error | valid |

**Pass totals:** A **25 valid / 5 invalid / 20 error / 0 timeout (50.0 %)** · B **25/5/20/0 (50.0 %)** ·
C **10/1/39/0 (20.0 %)** · D **9/2/39/0 (18.0 %)**.

### 3.2 Four-pass comparison — which knob rescued which model

- **A and B are identical (25 valid).** Strategy `:reuse` rescues nothing here; the only difference is
  `AdPlugin::HouseAd` goes `valid → invalid` under D (`:all`/`:reuse`).
- **Valid in all four (9):** `AdPlugin::HouseAdRoute`, `AdminDashboardSection`, `AdminNotice`,
  `AiApiRequestStat`, `ApiKeyScope`, `ApplicationRequest`, `AskAiReportSubjectAsk`, `AssociatedGroup`,
  `BackupMetadata`.
- **No model was rescued by `:all`** — C and D are pure regressions. 16 models that passed A fail under
  both C and D: the `:all` auto-builder walks `Topic → Category → User → UserEmail` and trips the
  username/email/color/emoji gaps, plus `Topic#category` FK-under-`:reuse` errors in D.
- **Pass A/B are the best knobs (50 %)**; `:all` costs 30–32 points.

**Dominant real-app failure signatures (A):** 15 errors share one cause — a nested `User` baked via
FK-parent persistence fails `Username must only include numbers, letters, dashes, dots, and
underscores, Primary email can't be blank`. The 5 invalids are app-specific format/state rules
(`examples` format, HTTPS URL, registered report source, LLM decision model, tool alias).

### 3.3 Out-of-box (pass A valid) — plain list

25 models: `AdPlugin::HouseAd`, `AdPlugin::HouseAdRoute`, `AdminDashboardSection`, `AdminNotice`,
`AiApiAuditLog`, `AiApiRequestStat`, `AiMcpOauthToken`, `AiSecret`, `AiToolAction`, `AllowedPmUser`,
`AnonymousUser`, `ApiKey`, `ApiKeyScope`, `AppearanceChange`, `ApplicationRequest`, `AskAiLog`,
`AskAiReport`, `AskAiReportSubject`, `AskAiReportSubjectAsk`, `AssociatedGroup`, `BackupMetadata`,
`Badge`, `BadgeGrouping`, `BadgeType`, `BaseTimer`.

### 3.4 Needs define — 19 models, working custom factories

Real file: `.smoke-tests/real-app-cache/discourse/app/smoke_definitions.rb`, `require`-loaded via
`SMOKE_DEFINITIONS`. Loading these + re-baking pass A lifted **25 → 43 valid (86 %)**, i.e. **19 rescued**
(net +18: one pass-A-valid model, `ApiKey`, regressed under the defines — see §3.5).
Key snippets:

```ruby
# Discourse sets belongs_to_required_by_default = false -> break User/UserEmail cycle
FactoryBakery.define(UserEmail) { user { nil } }

FactoryBakery.define(User) do
  username { "fb_#{SecureRandom.hex(5)}" }          # 20-char alphanumeric validator
  password { 'SmokePass123!' }
  secure_identifier { SecureRandom.hex(12) }        # unique index collision
  primary_email do
    FactoryBakery.bake(UserEmail, email: "fb_#{SecureRandom.hex(5)}@example.com", primary: true)
  end
end

FactoryBakery.define(Category) do
  color { 'FF0000' }; text_color { '00FF00' }       # /\A(\h{6}|\h{3})\z/ synthesis gap
  emoji { nil }                                     # emoji_exists needs a real Emoji row
end

FactoryBakery.define(AccessControlList) do
  target_id { nil }; target_type { nil }
  association(:target) { |_owner| FactoryBakery.bake(Group) }
end
FactoryBakery.define(AiSummary) do
  target_id { nil }; target_type { nil }
  association(:target) { |_owner| FactoryBakery.bake(Topic) }
end
FactoryBakery.define(Assignment) do
  assigned_to_id { nil }; assigned_to_type { nil }
  association(:assigned_to) { |_owner| FactoryBakery.bake(User) }
end

FactoryBakery.define(AiAgent) { examples { [] } }   # skip malformed-examples validator
FactoryBakery.define(AdPlugin::AdImpression) do
  ad_type { :adsense }; ad_plugin_house_ad_id { nil } # enum + external-ads consistency
end
FactoryBakery.define(AiMcpServer) { url { 'https://discourse.org' } }
FactoryBakery.define(Blog::Path) { path { "/smoke-path-#{SecureRandom.hex(6)}" } }
FactoryBakery.define(Blog::Publication) { path { "/smoke-pub-#{SecureRandom.hex(6)}" } }
```

Rescued models: `AccessControlList`, `AdPlugin::AdImpression`, `AiAgent`, `AiAgentMcpServer`,
`AiArtifact`, `AiArtifactKeyValue`, `AiArtifactShare`, `AiArtifactShareKeyValue`, `AiMcpServer`,
`AiPostImageCaption`, `AiReviewableSuggestion`, `AiSpamLog`, `AiSummary`, `AiTool`,
`BackupDraftPost`, `BackupDraftTopic`, `Blog::Publication`, `Blog::Review`, `Blog::ReviewFeedback`.

### 3.5 Still failing — 6 pass-A residuals, diagnosis

| model | status | diagnosis |
|---|---|---|
| `AdminDashboardReport` | invalid | **App-inherent.** `source_must_be_registered` requires a report source in Discourse's registry; no attribute define can register one. |
| `AiModerationSetting` | invalid | **App-inherent.** Needs a configured LLM/decision model for spam detection — full-boot site-setting state. |
| `AiToolSecretBinding` | invalid | **App-inherent-ish.** `Alias 'JJJ' is not declared in this tool` — the alias must match the bound tool's declared contract; would need a coordinated `AiTool` define plus persisted tool graph. |
| `Assignment` | error | **Needs more defines.** A nested `Assignment#target` required polymorphic edge (distinct from `assigned_to`) is still undeclared; another `association :target` block would be needed. |
| `AiArtifactVersion` | error | **DB-state collision.** `Slug is already in use` — a nested `Blog::Path`/slug uniqueness conflict against rows persisted by earlier `bake!` calls in the same process. |
| `Blog::Path` | error | **DB-state collision.** `Slug is already in use` despite a random path define — the uniqueness validator checks the normalized slug against persisted rows; needs a clean DB or a globally-unique slug domain. |

**Define-induced regression:** `ApiKey` was valid under pass A but became `invalid` after the defines
(`Api key scopes at least one must be selected`). The global `User`/`Category` defines changed nested
generation enough to drop the scope rows. A targeted `association :api_key_scopes, count: 1` define
would restore it — this is a define-graph side effect, not a base-gem failure.

**Gem gaps exposed by Discourse (name + sketch):**
1. `/\A(\h{6}|\h{3})\z/` (Category `color`/`text_color`) — synthesizer emits `hhhhhh` (non-hex) 10×.
   Sketch: teach `RegexSynthesizer` that `\h` is `[0-9a-fA-F]` and seed from it.
2. `Blog::Publication#path` complex URL-segment regex with `%2b`/`%hh` escapes — synthesizer emits
   malformed escapes. Sketch: a URL/path value generator keyed on the validator shape.
3. `User#primary_email` has_one + `UsernameValidator` + `SecureIdentifier` uniqueness — the gem's
   heuristic filler cannot produce a valid nested `UserEmail` without a define. Sketch: has_one
   auto-build for `validates_associated` children under `required_only`.

### 3.6 Does `.define` handle 100 % of Discourse? — **No.**

Out-of-box **50 %** → with `.define` **86 %**. Residue: **6 pass-A models** — 3 need full-boot
registry/AI state, 2 are DB-state collisions from persisted fixtures, 1 needs one more polymorphic
define — **plus 1 define-induced regression** (`ApiKey`).

---

## 4. Summary

| app | out-of-box (A) | + `.define` | still failing | combined coverage | 100 % with `.define`? |
|---|---|---|---|---|---|
| Mastodon | 17/50 = **34 %** | +28 → 45/50 | 5 | **90 %** | **No** — 5 residual (app-inherent/state) |
| Discourse | 25/50 = **50 %** | +19 → 43/50 (net +18) | 6 (plus 1 define-induced regression) | **86 %** | **No** — 6 residual + 1 regression |

**Direct answer:** with `.define` factories, FactoryBakery does **not** handle 100 % of the cases in
either real app. It reaches 90 % (Mastodon) and 86 % (Discourse). The honest residue is 5 models in
Mastodon and 6 in Discourse (+1 define-induced regression), dominated by
**full-boot state that an unsaved attribute factory cannot manufacture** — persisted follow/visibility
relationships, registered report sources/LLMs, resolvable remote accounts, uniqueness against rows
already in the DB — plus a small set of **regex-synthesis gaps** (`\h`, combined username regexes,
complex URL paths) that are real, actionable gem improvements.

Every script fix is in the skill script; all outputs are uncommitted under
`.smoke-tests/real-app-cache/` and this report. No gem `lib/` files were touched; nothing was committed
or pushed.
