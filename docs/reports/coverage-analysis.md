# Coverage analysis — can FactoryBakery support 100% of real-world Rails models? (Mastodon + Discourse)

**Date:** 2026-11-19
**Question:** of every failure class and unsupported use case observed in the two real-app smoke runs, which are worth gem customization (a), which are coverable today via `.define` (b), and which are app-inherent (c)? What is the honest path to 100%?

## Executive summary

| bucket | share of the 100 in-window baked models* | meaning |
|---|---|---|
| **valid out of the box** | **54 %** (M 14/50 + D 40/50) | heuristic bake + `valid?(:create)` passes, plugin on, no user code |
| **(b) coverable today via `.define`** | **5 %** | proven in this audit: a define file makes the bake VALID (5 models) |
| **(a) requires gem work** | **1 %** | one in-window model is blocked by an open gem defect |
| **(c) app/harness-inherent** | **40 %** | full-app boot, extraction artifacts, app-lib coupling — no reasonable filler can help |
| **honest ceiling today (harness)** | **59 %** | 54 % + the proven defines; closing the (a) list adds only ~1 % *in-harness* |
| **projected ceiling on a fully-booted real app** | **~93 % today (with defines) → ~95 % after the (a) list** | Mastodon's 35-model (c) mass is dominated by *no-boot harness artifacts* (missing app config, partially-extracted classes) that disappear in a real checkout; the irreducible residue (~5 %) is validators coupled to booted app state |

\* denominator: the two 50-model smoke windows (first 50 distinct loadable models per app). Class exposure beyond the windows is quantified against the full loadable surface (Mastodon 118, Discourse 239 concrete models) in the tables below — the windows understate (a) because they sample the alphabet, not the failure surface.

Key structural finding: **Mastodon's in-window failures are almost entirely environment, not gem, problems** (35 of 36 errors trace to one no-boot chain plus one partially-loaded class), while **Discourse's residual failures are split between real gem gaps (2), define-recipe knowledge (4), and boot coupling (5)**. The gem-relevant (a) work is justified by cross-app class counts — the blank-default routing fix alone touches 24 models across both apps, raw-FK presence 27, format synthesis 9 (and it gates the entire Mastodon account graph), PG arrays ~44.

## Provenance

| | |
|---|---|
| Gem under test | working tree, branch `mohd/v0.0.2`. Parallel agents committed throughout the audit (V1–V6 fillers, associations plugin, JsonFiller `38a96e7`, memoization `3ef9c37`); every finding in this report was **re-verified on the final clean tree @ `3ef9c37`** |
| Mastodon | cached deterministic pipeline entry `.smoke-tests/deterministic-smoke-cache/mastodon/` (clone @ `aa80465660c6`, plugin-on `last-run.jsonl` @ gem `9f72cfc`: 14 valid / 0 invalid / 36 error). All 14 valid re-probed VALID on the final tree |
| Discourse | the recorded run was the direct-harness workspace (`factory_bakery-smoke/discourse` clone @ `88fecc31`, gem `4fcc507`, core-only: 45/2/3). **A deterministic-cache entry was never created for Discourse** — this audit re-used the old workspace, re-baking the full first-50 window on the current tree: **40 valid / 2 invalid / 8 error** (plugin on) |
| Method | runner-bootstrap probes in each harness (`bin/rails runner` / plain-AR boot), per-failure defines baked and validated empirically; class-exposure censuses over all 118 (M) + 239 (D) loadable models; FFaker synthesis sampled 3× per regex under an 8 s timeout |
| Repo impact | read-only except this file. Nothing committed, nothing pushed |

## Result snapshots

### Mastodon (50-model window)

- Recorded (gem `9f72cfc`, plugin on, post-V2): **14 valid / 0 invalid / 36 error** — 35 × `Mastodon::Version.prerelease` chain + 1 × `InverseOfAssociationNotFoundError` (Backup).
- Re-probe of the 14 valid on the final tree: all VALID.
- Define rescue experiment (see snippets): `CustomEmoji` (one of the 35 error models) bakes **VALID ×3, persists under `bake!` twice** with a 6-line define. The other 34 error models root in `Account` (auto-built parent) and are **walled off in the harness** by two artifacts: the no-boot `Mastodon::Version`/`Request` chain, and a partially-extracted `User` class (`Account.new.valid?` itself raises — see c2).

### Discourse (50-model window)

- Recorded (gem `4fcc507`, core-only): 45/2/3 = 90 %.
- Current tree, plugin on: **40 valid / 2 invalid / 8 error** = 80 %. Deltas vs the recorded run are *policy drift in the gem, not app drift*: `+1` valid (CategoryPostingReviewGroup — required-belongs_to auto-build landed), `−6` (ApiKey invalid via enum-gate exposure [the recorded pass was 1-of-3 luck]; Category invalid via raw-FK presence + unsaved parent; AccessControlList/BackupDraftPost/CategoryFormTemplate/CustomEmoji error via polymorphic-raise / parent load gap / proc-length crash / `user_id ||=` boot chain).

## Per-failure-class table

Bucket = the class's classification. Proof/plan cites the section with the empirically verified evidence.

### Landed during the audit window (gem already grew these — documented for the path-to-100% story)

| # | class | apps hit | models | bucket | status / proof |
|---|---|---|---|---|---|
| L1 | required `belongs_to` presence | M (29 invalids in core run), D (1) | 30 in-window | (a) landed | associations plugin auto-build; M 29 invalids → 0, D CategoryPostingReviewGroup invalid → **VALID (re-probed)** |
| L2 | blank DB default defeats *presence* | M (4) | 4 | (a) landed (V2) | M Announcement/DomainAllow/DomainBlock/EmailDomainBlock invalid → 0 |
| L3 | uniqueness unenforced | M+D broadly | — | (a) landed (V1) | `UniquenessEnforcer` probes via the model's own validator; `bake!` ×2 on defined CustomEmoji → ids 1, 2, both valid |
| L4 | Proc `:in` evaluated eagerly at filler-init | D (BaseTimer) | 1 | (a) landed (V4) | failure moved from `common_validators.rb` filler-init to bake-time lazy call — the *residual* is the app constant (`c3`) |
| L5 | symbol/proc comparison options crash | (audit probes) | — | (a) landed (V3) | validators-coverage probes P16/P17 |
| L6 | numeric hygiene (`other_than`, parity bounds) | (audit probes) | — | (a) landed | `2df8233` |
| L7 | json/jsonb columns fed Strings | D (AppearanceChange), M (11 json-column models) | 75 jsonb columns / 53 tables (D), 11 models (M) | (a) landed | `JsonFiller` (`38a96e7`) routes on column type; **proven under faithful typing** (b5 below). Old Discourse workspace translated jsonb→TEXT, so its column type no longer routes — see harness recommendations |
| L8 | format values returned unverified | D (ColorSchemeColor "Hex is invalid" @ `4fcc507`) | 9 format-validated attrs across both apps | (a) landed (V5) | verify-then-raise (`ca8f120`): ColorSchemeColor now fails *loudly* with a precise constraint error instead of an invalid record. Synthesis itself remains open (A1) |

### Open (a) — worth gem customization

| # | class | apps hit | models (in-window / full surface) | bucket | evidence / sketch |
|---|---|---|---|---|---|
| A1 | **format regex synthesis** — FFaker `from_regexp` emits literals for groups/alternation/inline-flag constructs (`"(ddd|cccccc)"`, `"(i-mx:666(-..ff)f)/"`), spins unboundedly on POSIX/unicode classes | M: Account#username, FeaturedTag#name, Keypair#local_fragment, Tag#name, Tag#display_name, UserRole#color; D: ColorSchemeColor#hex, ThemeField#name, WebHook#payload_url | 2 in-window / **9 models across both apps** (7 of 8 M regexes, 3 of 3 D regexes unsynthesizable) | **(a)** | ColorSchemeColor raises the V5 exhaustion error in-bake; `bake(Tag)` **times out >30 s** inside the filler — this is also the recorded `FeaturedTag` >20 s smoke-timeout root cause, now explained. Amplification: unsynthesizable `username` blocks the whole Mastodon account graph. Sketch: bounded structural regex walk (alternation, classes, quantifiers, inline flags) + per-attempt timeout + template library for common shapes (hex, slug, username, url); exhaustion raises the existing V5 error. Effort **M–L** |
| A2 | **blank DB defaults defeat non-presence value validators** — defaulted columns route to NoopFiller unless *presence* needs a value, so format/length/uniqueness/inclusion see `""` | M: Account, AccountAlias, Appeal, CanonicalEmailBlock, CustomEmoji, CustomFilterKeyword, DomainAllow, DomainBlock, EmailDomainBlock, Identity, List, Marker, PreviewCard, PreviewCardProvider, Relay, Report, Rule, RuleTranslation, SiteUpload, Tag, UnavailableDomain, UserRole, Webhook; D: Tag#slug, WebHook#secret | 1 in-window (masked) / **24 models across both apps** | **(a)** | CustomEmoji#shortcode (Format+Length min 2, default `""`) — observed invalid; `Account#username` (Format+Length) — observed raise after define unmasking; Tag#name, Marker#timeline, UserRole#color projected. The uniqueness-only subset (Domain* trio, 17 M models) bakes "valid" with blank junk — a data-quality hole (see luck section). Sketch: extend the `FillerSelector` presence escape hatch to any value-shaping validator (format/length/uniqueness/inclusion/numericality) on defaulted columns. Effort **S** |
| A3 | **raw-FK presence validators cannot be satisfied by unsaved auto-built parents** — `validates :user_id, presence: true` (the column, not the association) needs a non-nil integer; an unsaved parent instance has `id == nil` | D: 25 models (36 FK attrs; Category, CustomEmoji, EmailToken, UserBadge, TopicTimer, …); M: 2 (Marker#last_read_id, WebauthnCredential#external_id — non-association FKs) | 2 in-window (Category, CustomEmoji-D) / **27 models** | **(a)** | D Category: "User can't be blank" with a built-but-unsaved parent; D CustomEmoji: `user_id \|\|= Discourse.system_user` chain fires because the auto-built user's id is nil. Sketch: for FK-validated edges, either persist the parent (bake!-graph mode) or offer an explicit FK-value fallback; document the unsaved semantics. Effort **M–L**. Interim define proven (b4) |
| A4 | **PG array columns** routed to StringFiller (SQLite adaptation drops `array:`, but on real PG `column.array?` is routable and String values feed array-expecting model APIs) | M: CustomFilter#context (`.map` crash — recorded), Account#attribution_domains (`normalizes` read-crash), Conversation, AccountMigration, Poll, Status*, User#chosen_languages …; D: 49 array columns / 32 tables (access_control_lists, api_keys, user_options, theme_modifier_sets, …) | 0 in-window unmasked / **~44 models/columns across both apps** | **(a)** | Both recorded crashes (M CustomFilter, D AppearanceChange-class) are this family; Discourse's array columns pass today only because nothing in-window reads them. Sketch: route on `column.array?` → ArrayFiller of element-type values (mirror JsonFiller); keep array info in the Discourse cache translation. Effort **S–M** |
| A5 | **proc/symbol length options crash** — `Integer > Proc` in `adjust_length` (`string_filler.rb:194`) | D: FormTemplate#name/#template (`maximum: -> { SiteSetting.… }`); M: none | 1 in-window (CategoryFormTemplate, via auto-built parent) / 2 models | **(a)** | observed ArgumentError; the only in-window model whose validity needs gem work. Sketch: resolve proc/symbol `:minimum/:maximum/:is/:in` at bake time like V3/V4 did for comparison/inclusion; clean error when a proc needs booted constants. Effort **S** |
| A6 | **Paperclip attachment-adjacent columns** — `*_remote_url` gets URL-shaped heuristic fills that trigger download machinery; `*_file_name`/`*_content_type` filled incoherently, tripping attachment validators | M: Account (avatar/header), CustomEmoji (image), MediaAttachment (file/thumbnail), PreviewCard (image), PreviewCardProvider (icon), Backup (dump) | 2 in-window roots (Account, CustomEmoji) / **7 attachments on 6 models**, amplifying to the 35-model M mass | **(a)** for the coherent-fill half; the download machinery itself is (c1) | the URL heuristic (`/url|website|link/` → `http_url`) is the *trigger* of the M Version mass; the Paperclip trio define made attachment validators pass (b6). Sketch: benign values for `*_remote_url`, coherent file_name/content_type pairs (optionally read Paperclip's content-type allowlist). Effort **S–M** |
| A7 | **robustness: reflection walks on partially-loaded classes** — `BackEdgeDetector` calls `.foreign_key` on a reflection whose `inverse_of` is nil (partial `User`), crashing `derive_foreign_key` | M harness | blocks every plugin build of an Account-rooted model on the current tree | **(a)** | reproduced on final tree `3ef9c37` (`bake(AccountAlias)` → `NoMethodError: undefined method 'foreign_key' for nil` at `back_edge_detector.rb:34`). Not a use-case gap — a hardening item: rescue/skip reflections that raise during edge detection. Effort **S** |

### (b) — coverable today via `.define` (all proven in this audit)

| # | class | models | proof |
|---|---|---|---|
| b1 | app-domain value shapes (hex colors, slugs, …) | D ColorSchemeColor (+ M Tag/UserRole recipe) | **b6/B1 snippet: VALID ×3** |
| b2 | enum/boolean gate draws flip dormant conditional validators (`:if/:unless` read attributes the heuristics fill; the "conditionals only relax" assumption is wrong) | D ApiKey (`scope_mode` → scope validators; the recorded 90 % run passed it by 1-of-3 enum luck); M Account (`domain` fill → `local?` false → conditional `uri`/`inbox_url` presence). Exposure: 19 D + 25 M enum models, 67 D + 48 M boolean models | **B2/B6 snippets: VALID ×4 / recipe documented** |
| b3 | required polymorphic belongs_to (the plugin raises a clean, instructive error — the DSL is the designed answer) | D AccessControlList | **B3 snippet: VALID ×3** |
| b4 | raw-FK presence, unsaved-bake semantics (interim until A3) | D Category | **B4 snippet: VALID ×3** (caveat: `user_id: 1` dangles on save) |
| b5 | jsonb semantic shape (random Hash keys can violate app key allowlists; JsonFiller covers the *type*, defines cover the *shape*) | D AppearanceChange | **B5 snippet: VALID ×3** under faithful json typing |
| b6 | attachment URL chain + Paperclip trio + blank-default shortcode (full stack) | M CustomEmoji | **B6 snippet: VALID ×3, `bake!` persisted ×2** |

### (c) — app-specific, not the gem's business

| # | class | models | why no reasonable filler can help |
|---|---|---|---|
| c1 | `Mastodon::Version` / `Request` download machinery — assigning a URL-shaped value to `*_remote_url` constructs an HTTP `Request` whose headers read repo config (`version_configuration` is nil without app boot); in a *real* booted app the same fill would attempt actual network fetches (and `suppress_errors: false` would raise) — a factory must not do side-effect I/O on assign | M: 35-model mass (34 via auto-built Account + CustomEmoji own chain) | needs full app config; and no heuristic can know a column setter performs I/O. Define-interruptible — proven (CustomEmoji; Account recipe below) — but the machinery itself is app business |
| c2 | partially-extracted classes (sparse checkout lacks `app/services`, `app/indices`) → `User` half-loads → `Account.new.valid?` raises `InverseOfAssociationNotFoundError` (its `has_one :user, inverse_of: :account` can't resolve the inverse) | M: Backup (direct); the whole Account graph's recovery wall | harness extraction artifact; in a real checkout User loads completely and the error vanishes. Recommendation: extend the sparse checkout, as the M report already notes |
| c3 | boot-dependent app constants inside custom validators / procs / callbacks | D: AdminDashboardReport (`AdminDashboard`), BaseTimer (`BaseTimer::Enum` inside the inclusion proc — V4's lazy eval still needs the constant), CustomEmoji (`Discourse.system_user` in `before_validation`, reached via the A3 unsaved-id chain) | no value the gem supplies can make an app constant resolve without the app booted |
| c4 | missing app assets / i18n in the no-boot harness | D: ApiKey's error *label* ("Translation missing: …"); M load_errors: AnnouncementReaction (emoji_map.json), PrivacyPolicy/TermsOfService (config templates) | cosmetic in D's case (the underlying gate is b2); genuine file dependencies in M's |
| c5 | model files that cannot load standalone in the harness | D: BackupDraftPost (`Post` fails the two-pass require — missing `Topic::RateLimiter` lib chain); M's 50 recorded load_errors | extraction surface, not the bake surface; recommend widening the sparse checkout / upstream_lib set |

## The proven `.define` snippets (b)

All run in the real harnesses against the final gem tree; each result line is verbatim probe output.

**B1 — Discourse `ColorSchemeColor`** (format-synthesis gap, app-domain shape):

```ruby
FactoryBakery.define(ColorSchemeColor) do
  hex { SecureRandom.hex(3).upcase }   # satisfies /\A([0-9a-fA-F]{3}|[0-9a-fA-F]{6})\z/
end
# ColorSchemeColor #1: VALID   #2: VALID   #3: VALID
```

**B2 — Discourse `ApiKey`** (enum-gate flip; the recorded 90 % run passed this model on a 1-in-3 draw):

```ruby
FactoryBakery.define(ApiKey) do
  scope_mode { :global }   # benign enum value; read_only?/granular? gates stay closed
end
# ApiKey #1: VALID  #2: VALID  #3: VALID  #4: VALID  (baseline: ~2/3 invalid)
```

Note the trap this exposed: `read_only { false }` is a silent no-op — `read_only?` is an enum predicate, `read_only` is not an attribute, and the builder's `respond_to?` check skips the assignment without complaint.

**B3 — Discourse `AccessControlList`** (required polymorphic; the plugin's raise names the fix):

```ruby
FactoryBakery.define(AccessControlList) do
  association :target, factory: Category   # must be a class or a registered symbol — a String target raises
end
# AccessControlList #1: VALID   #2: VALID   #3: VALID
```

**B4 — Discourse `Category`** (raw-FK presence, unsaved-bake semantics — interim until A3 lands):

```ruby
FactoryBakery.define(Category) do
  user_id { 1 }   # passes validates :user_id, presence: true for an unsaved bake;
                  # for bake! use A3's persisted parents or strategy: :reuse with a saved user
end
# Category #1: VALID   #2: VALID   #3: VALID
```

**B5 — Discourse `AppearanceChange`** (jsonb semantic shape; the recorded run's `keys-for-String` error):

```ruby
# The old workspace translated jsonb -> TEXT, so the column no longer routes to JsonFiller and
# every value re-casts to a String on read. With faithful typing (what the deterministic cache
# should produce, and what real PG gives):
AppearanceChange.attribute :site_settings, ActiveRecord::Type::Json.new

FactoryBakery.define(AppearanceChange) do
  site_settings { {} }   # keys - SITE_SETTING_NAMES == [] passes vacuously
end
# AppearanceChange #1: VALID   #2: VALID   #3: VALID
```

**B6 — Mastodon `CustomEmoji`** (full stack: attachment URL chain → Paperclip trio → blank-default shortcode; the model was an *error* in every recorded run):

```ruby
FactoryBakery.define(CustomEmoji) do
  image_remote_url { nil }               # interrupts the Request/Version download chain (c1 trigger)
  image_file_name { 'emoji.png' }        # coherent Paperclip trio satisfies
  image_content_type { 'image/png' }     # validates_attachment_content_type
  shortcode { "emoji_#{SecureRandom.hex(3)}" }  # A2: blank default "" defeats Format+Length(min 2)
  domain { nil }                         # b2: keeps local? true so the shorter length cap applies
end
# bake #1: VALID  #2: VALID  #3: VALID
# symbol target FactoryBakery.bake(:custom_emoji): VALID
# bake! (persisted): id=1 valid=true     bake! #2: id=2   ← uniqueness survives persistence
```

**Account recipe (M, blocked at the (c2) wall — documented to show where the gem ends and the harness artifacts begin):**

```ruby
FactoryBakery.define(Account) do
  avatar_remote_url { nil }        # c1 trigger removed
  header_remote_url { nil }
  username { "user_#{SecureRandom.hex(4)}" }  # A1: both username regexes unsynthesizable by FFaker
  attribution_domains { nil }       # A4: the only readable value on the adapted schema; any
                                    # Array/String crashes Mastodon's normalizes proc on read
  domain { nil }                   # b2: keeps local? so conditional uri/inbox_url presence stays off
  avatar_file_name { 'avatar.png' }        # A6 trio
  avatar_content_type { 'image/png' }
  header_file_name { 'header.png' }
  header_content_type { 'image/png' }
end
# baseline:      ERROR Mastodon::Version.prerelease (NoMethodError for nil[])
# after define:  ERROR ActiveRecord::InverseOfAssociationNotFoundError
#                (Could not find the inverse association for user (:account in User))
# — every gem-relevant layer is cleared; what remains is the partially-extracted User (c2).
# Plain Account.new.valid?(:create) raises the same error with NO gem involvement.
```

## Prioritized (a) list

Ranked by models-hit-per-effort across both apps:

1. **A2 — blank-default routing** (S): 24 models; a one-line precedence extension of the existing V2 escape hatch. Highest confidence fix.
2. **A1 — format synthesis engine** (M–L): 9 models directly, gates the entire Mastodon account graph (`username`), and converts today's *hangs* (Tag/FeaturedTag unbounded spins) into bounded errors even before synthesis is solved.
3. **A3 — persisted parents for raw-FK-validated edges** (M–L): 27 models, all Discourse-heavy; ties into the `bake!` graph design. Interim: fill the FK when the edge is validated on the column (validation-only semantics, like b4).
4. **A4 — ArrayFiller for `column.array?`** (S–M): ~44 models/columns; mirror the freshly-landed JsonFiller; requires the Discourse cache translation to preserve array typing.
5. **A5 — proc/symbol length options** (S): crash class, 2 models, trivial bake-time resolution.
6. **A7 — reflection-walk hardening** (S): rescues around `foreign_key`/inverse derivation so one broken class cannot take down every Account-rooted build.
7. **A6 — attachment-aware filling** (S–M): 6 models + the c1 trigger; even just "never URL-fill `*_remote_url`" removes the worst side-effect class in legacy Rails apps.

Landed-but-recommended follow-ups: keep the Discourse deterministic-cache schema faithful (json/arrays typed, not flattened to TEXT — the old workspace's translation is what made AppearanceChange's define need the type patch); widen the Discourse sparse checkout so `Post` (and its lib chain) loads — BackupDraftPost's parent bake depends on it.

## What remains app-inherent (the irreducible ~5 %)

1. Validators/callbacks that call booted app state: `AdminDashboardReport#source_must_be_registered` (AdminDashboard), `BaseTimer.types` (`BaseTimer::Enum`), Discourse `CustomEmoji#set_default_user_id` (`Discourse.system_user`). In a booted app these *work* — they are only failures in the no-boot harness; the gem's honest contract there is a clean error, not validity.
2. Setters with side-effect I/O (Mastodon's `remotable_attachment` download chain): no generic filler can know assigning a column performs HTTP; factory authors pin `*_remote_url { nil }` — exactly what Mastodon's own fabricators do — and the gem's contribution is A6 (stop handing such setters URLs).
3. Harness extraction artifacts (partial `User`, missing `app/services`, asset files): transient to the smoke pipeline, invisible to real users of the gem inside these apps.
4. i18n-dependent *messages* (not logic) — cosmetic.

## "Valid today but only by luck" — patterns the windows hide

- **ApiKey (D)**: the recorded 90 % run passed on a 1-of-3 enum draw (`scope_mode` = global). Any re-run of the recorded smoke could have scored 88 %.
- **DomainAllow / DomainBlock / EmailDomainBlock (M)**: bake "valid" with `domain = ""` — blank junk satisfying only an (empty-table) uniqueness check. Semantically empty fixtures; A2 fixes the class.
- **Boolean presence draws**: the validators audit measured 50 % invalid rates on `validates :flag, presence: true` before V2; the windows contained no such column.
- **Category / AccessControlList / BackupDraftPost / CategoryFormTemplate / CustomEmoji (D)**: all recorded valid @ `4fcc507`, all failing on the current tree — each traced to *gem policy drift* (FK-nil rule, auto-build raising on polymorphic/missing parents, proc-length storage), not to Discourse changing.
- **Tag / UserRole / Marker / Keypair (M)**: outside the 50-window; `bake(Tag)` currently *times out* (>30 s FFaker spin), `UserRole`/`Marker` pass (allow-blank/enum routing) despite census-level unsynthesizable regexes — the census is regex-level; per-model impact depends on conditionals.

## Model-level accounting (how the 100 add up)

| | out-of-box | (b) proven | (a) open | (c) inherent |
|---|---|---|---|---|
| Mastodon 50 | 14 | 1 (CustomEmoji) | 0 in-window¹ | 35 (Version mass c1 + Backup c2) |
| Discourse 50 | 40 | 4 (AccessControlList, ApiKey, Category, ColorSchemeColor) | 1 (CategoryFormTemplate, A5) | 5 (AdminDashboardReport, BaseTimer, CustomEmoji c3; AppearanceChange old-harness artifact; BackupDraftPost c5) |
| **total** | **54** | **5** | **1** | **40** |

¹ Mastodon's in-window (a) exposure is *masked* by (c): the census shows the (a) classes hitting out-of-window models hard (Tag timeout, 22 blank-default models, 11 json models, ~12 array models). In a fully-booted Mastodon, the 35-model (c) mass converts to (a)/(b) territory — which is why the *class-level* (a) list matters more than the in-window 1 % suggests.

## Reproduction appendix

```bash
# Mastodon harness (cache entry), plugin on, boot replicating the pipeline RUNNER:
cd .smoke-tests/deterministic-smoke-cache/mastodon/harness
mise exec ruby@3.4.3 -- bin/rails runner $PROBE   # PROBE = boot + targeted bakes (see audit probes)

# Discourse direct-harness (old workspace):
cd "$TMPDIR/factory_bakery-smoke/discourse"
BUNDLE_GEMFILE=$PWD/Gemfile mise exec ruby@3.4.3 -- ruby $PROBE
```

Audit artifacts (censuses, per-model re-test JSON) lived in the session temp dir and are summarized inline above; the harnesses, clones and `last-run.jsonl` remain under `.smoke-tests/deterministic-smoke-cache/mastodon/` and the Discourse workspace respectively.
