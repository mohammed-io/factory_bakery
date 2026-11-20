# Real-world smoke report after the defect fixes — Discourse (2026-11-20)

Full-boot rerun of every Discourse model (core plus bundled plugins) after the
ten smoke-found defects from
[the 2026-11-19 run](20261119-final-discourse.md) were fixed. Same app clone,
PostgreSQL (`fb_probe_pg:55432`, `discourse_development` loaded from the app's
real `db/structure.sql`), Redis (`fb-smoke-redis:56379`), runner, definitions
file ([`20261119-final-discourse-definitions.rb`](20261119-final-discourse-definitions.rb))
and `SMOKE_TIMEOUT=30`. Only the gem changed: `af756ed` → `e207d72`
(`mohd/v0.0.2`).

414 eligible AR models, four passes per round (A = `required_only/fresh`,
B = `required_only/reuse`, C = `all/fresh`, D = `all/reuse`). Each bake is
`FactoryBakery.bake(Model)` under `FactoryBakery::Associations.with(mode:, strategy:)`,
checked with `valid?(:create) || valid?`, with the attachments plugin active.

---

## 1. Summary

### Automatic round: no app definitions

| Pass | Mode / strategy | Models | Valid | Invalid | Error | Timeout | Pass rate | 2026-11-19 valid | Δ |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| A | required_only / fresh | 414 | **359** | 23 | 32 | 0 | **86.7 %** | 327 | +32 |
| B | required_only / reuse | 414 | **382** | 23 | 9 | 0 | 92.3 % | 376 | +6 |
| C | all / fresh | 414 | **249** | 17 | 148 | 0 | 60.1 % | 81 | **+168** |
| D | all / reuse | 414 | **374** | 28 | 12 | 0 | **90.3 %** | 308 | +66 |

### Definitions round: `20261119-final-discourse-definitions.rb`

| Pass | Mode / strategy | Models | Valid | Invalid | Error | Timeout | Pass rate | 2026-11-19 valid | Δ |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| A | required_only / fresh | 414 | **368** | 19 | 27 | 0 | **88.9 %** | 366 | +2 |
| B | required_only / reuse | 414 | **386** | 20 | 8 | 0 | 93.2 % | 383 | +3 |
| C | all / fresh | 414 | **332** | 17 | 65 | 0 | **80.2 %** | 129 | **+203** |
| D | all / reuse | 414 | **381** | 23 | 10 | 0 | 92.0 % | 313 | +68 |

### Headline

- Automatic pass A is at **86.7 %** (80 % goal: met, +6.7 pts). It rose by
  32 models.
- `:all` works. With definitions, pass C went from 31.2 % to 80.2 %. Automatic
  pass D went from 74.4 % to 90.3 %.
- One defect accounts for most of the automatic pass C gap. On 2026-11-19,
  269 models failed with `Primary email can't be blank`. 127 of them are now
  valid, and **98** still fail in `:all` with a fresh `User` (§5.1). Reuse (D)
  avoids it by picking an existing user, and the definitions round avoids it by
  declaring `User`.
- The definitions round dropped −1 in A. That model, `LlmFeatureCreditCost`,
  fails at random at both snapshots: a random LLM provider sometimes requires
  `region` (§5.3).

Raw JSONL:
`/Users/mohammed/Projects/factory_bakery/.smoke-tests/real-app-cache/discourse/fix3-auto.jsonl`
and `…/fix3-defined.jsonl` (2026-11-19 baseline: `final-auto.jsonl`,
`final-defined.jsonl`).

---

## 2. What was fixed, with code

The gem suite is at 1208 examples, 0 failures, 8 pending, with 100 % line and
branch coverage. Shared fixes, with code, are in
[the Mastodon report §2](20261120-fixes-mastodon.md#2-what-was-fixed-with-code):
in-graph identity, read-only models never saved, bounded `:all`,
remote-URL guard and graph-wide uniqueness. This section covers what moved
Discourse.

### 2.1 Bounded `:all` (C: 81 → 249 automatic, 129 → 332 defined)

On 2026-11-19 the C-pass errors were:

| Count | Error |
|---:|---|
| 269 | `RecordInvalid: Primary email can't be blank` |
| 23 | `PG::NotNullViolation` |
| 12 | `NameError: Missing model class ChatMessage for the Chat::MessageSearchData#chat_message association` |
| 2 | `MissingAttributeError: can't write unknown attribute 'left_side_id'` (HABTM join) |
| 1 | `CyclicAssociationError: DiscourseWorkflows::WorkflowVersion#workflow -> …` |

Models that became valid in C, grouped by their 2026-11-19 error:

| Newly valid | 2026-11-19 error | Examples |
|---:|---|---|
| 127 | `Primary email can't be blank` | `AiAgent`, `AiApiAuditLog`, `AiMcpServer`, `AiSecret` |
| 16 | `PG::NotNullViolation` | `AccessControlList`, `AppearanceChange`, `ChildTheme`, `ColorScheme` |
| 12 | `Missing model class ChatMessage` | `Chat::AllMention`, `Chat::GroupMention`, `Chat::HereMention`, `Chat::Mention` |
| 2 | `can't write unknown attribute 'left_side_id'` | `HABTM_WebHookEventTypes`, `HABTM_WebHooks` |
| 1 | `CyclicAssociationError: Boards::Column#board -> …` | `Boards::Column` |

```ruby
FactoryBakery::Associations.with(mode: :all) do
  FactoryBakery.bake(AiAgent)             # was "Primary email can't be blank"
  FactoryBakery.bake(Chat::Mention)       # was NameError ChatMessage; resolved via polymorphic_class_for
  FactoryBakery.bake(HABTM_WebHooks)      # was unknown attribute left_side_id
  FactoryBakery.bake(Boards::Column)      # was CyclicAssociationError on an optional edge
end
```

Optional edges are now built in a savepoint and dropped if they fail.
`CyclicAssociationError` is raised only for required edges. HABTM joins are
skipped, and a HABTM `left_side` reports its real FK. `polymorphic_class_for`
is used to resolve class names, so `ChatMessage` maps to `Chat::Message`.

### 2.2 JSON array shape

```ruby
# lib/factory_bakery/active_record_mapper/constraint_reader.rb (shape facts)
# json_shape is :array when the column default is an array, the serializer
# coder is Array, or the allowed values are arrays. JsonFiller then generates
# an Array, and a `serialize :x, type: Array` text column gets the ArrayFiller
# instead of a scalar String (which raised SerializationTypeMismatch).
```

### 2.3 Graph-wide uniqueness and unique-index-only columns

```ruby
# lib/factory_bakery/active_record_mapper/mapper.rb
def uniqueness_check(record, attr_name, value)
  return false unless uniqueness_validated?(record.class, attr_name)

  validators = uniqueness_validators_for(record.class, attr_name)
  return unique_index_taken?(record, attr_name, value) if validators.empty?
  # ... real validator otherwise
end
```

`users.secure_identifier` has a unique index but no validator. Before, it could
receive a value already in the table (`PG::UniqueViolation` on
`index_users_on_secure_identifier`). Now it is checked against the database
(`DiscourseWorkflows::ReviewableAgent` passes).

### 2.4 Verified optional fills, including the rebuild

```ruby
# lib/factory_bakery/fallback_builder.rb
def verify_rebuild!(attempt)
  object, builder = attempt
  return object unless builder.verification_needed?
  return object unless builder.optional_candidates?
  return object unless builder.optional_candidates.any? { |name| virtual_optional?(object, name) }

  verify_optional_fills!(attempt, nil)
end
```

`LlmModel#requested_vision_mode` is an `attr_accessor` with
`inclusion: { in: %w[disabled delegated native] }, allow_nil: true`. When the
rebuild filled it with `"delegated"`, `valid_vision_configuration` rejected the
record on another attribute. That fill is now reset to nil. With definitions,
`LlmModel` (A) went from 0/3 to 4/4 valid in probes.

### 2.5 Required strings never generated blank

```ruby
# lib/factory_bakery/attribute_fillers/string_filler.rb
BLANK = /\A[[:space:]]*\z/

def compliant?(value, context, lengths)
  return false if value.nil?
  return false if must_be_present? && BLANK.match?(value)
  # ...
end
```

`AdPlugin::HouseAd#name` has `presence: true` and a format that allows
whitespace, so about 1 bake in 8 produced an all-space name. This fix landed
after the final run (`9c5d49e`). Probes at `9c5d49e`: 12/12 valid. The
HouseAd failures in B/D of this run are this bug.

---

## 3. Works automatically

**ABCD (241 models)**, valid with no definition in every mode and strategy.
Examples: `AccessControlList`, `AdminNotice`, `AiAgent`, `ApiKey`, `Badge`,
`Boards::Board`, `BrowserPageviewEvent`, `Chat::ChannelArchive`,
`CategoryModerationGroup`, … (full list in `fix3-auto.jsonl`).

**ABD (107)**: valid everywhere except fresh `:all`, which is the §5.1 user
defect. This includes `Category`, `Topic`, `Invite`, `EmailToken`, the
`Reviewable*` family, `Topic*`, `Category*`, `AiArtifact*` and
`DiscourseEvents::*`.

**BD (22)**: valid only with reuse. A fresh build fails (A and C), for the
Boards models on a NOT NULL (§5.2):
`Boards::Card`, `Boards::CardHistory`, `DiscourseSolved::SolvedTopic`,
`TopicTimer`, `TopicViewItem`, `LlmQuota`, …

Newly valid in **A** (automatic, 33): `AdPlugin::AdImpression`, `AiArtifact`,
`AiArtifactKeyValue`, `AiArtifactShare`, `AiArtifactShareKeyValue`,
`AiArtifactVersion`, `AiPostImageCaption`, `AiSpamLog`, `BackupDraftPost`,
`Blog::Path`, `Blog::Revision`, `DiscourseEvents::Events::Event`,
`DiscourseEvents::Events::EventHost`, `DiscourseEvents::Events::Invitee`,
`EmbeddingDefinition`, `MovedPost`, `NestedViewPostStat`, `PolicyUser`,
`PostAction`, `PostCustomField`, `PostCustomPrompt`, `PostHotlinkedMedia`,
`PostLocalization`, `PostPolicy`, `PostPolicyGroup`, `PostSearchData`,
`QuotedPost`, `ReviewableHistory`, `ReviewableScore`, `SkippedEmailLog`,
`TopicEmbed`, `TopicEmbedAlias`, `UserStatus`.

Newly valid in **B** (automatic, 6): `AdPlugin::AdImpression`,
`Blog::Publication`, `Boards::CardHistory`, `DiscourseSolved::TopicAnswer`,
`LlmQuotaUsage`, `TopicLinkClick`.

```ruby
require 'factory_bakery/associations'
require 'factory_bakery/attachments'

FactoryBakery.bake(PostAction)          # newly valid in A and B
FactoryBakery::Associations.with(mode: :all, strategy: :reuse) do
  FactoryBakery.bake(Topic)             # valid; existing User/Category rows reused
end
```

---

## 4. Needs a definition

The 2026-11-19 definitions still apply. The models that fail in every pass and
round (ABCD) need app knowledge:

`AdminDashboardReport`, `AiModerationSetting`, `AiToolSecretBinding`,
`Bookmark`, `Chat::Channel`, `Chat::MessageSearchData`, `Chat::NullMessage`,
`DiscourseAutomation::Field`, `DiscourseChatIntegration::Channel`,
`DiscourseChatIntegration::Rule`, `FormTemplate`, `Live::Invite`,
`McpGroupScope`, `McpOauthClient`, `PostVotingComment`, `PostVotingVote`,
`Reviewable`, `ReviewableNote`, `SharedAiConversation`,
`SiteSettingLocalization`, `UserBadge`, `UserNotificationSchedule`,
`WatchedWordGroup`.

Typical causes are app-defined lists (`Provider is not a valid provider`,
`Scope is not included in the list`, `Type is not a valid filter`), YAML
templates (`Template is not a valid YAML string`), cross-field time rules
(`Day N start time is after end time`) and callbacks that assume a full graph
(`undefined method 'bot?' for nil`).

`ThemeTranslationOverride` in `:all` (C) also needs one. Under `:all` its
`Theme` gets an optional `settings_field` with random text, and the override's
own callback (`theme.settings`) parses it as YAML and raises
`ThemeSettingsParser::InvalidYaml`. A generic rule cannot know that a text
column must hold YAML:

```ruby
FactoryBakery.define(Theme) { skip :settings_field }
```

---

## 5. Still failing and what is next

### 5.1 `:all` + fresh `User` (98 models with `Primary email can't be blank`, plus 29 on `uploads.user_id`, automatic C)

`User has_one :primary_email` with `validates :primary_email, presence: true`.
In required-only mode the required `has_one` is built and `bake!(User)` works.
In `:all`, `bake(User)` is valid on its own, but `bake!(User)` fails:

```ruby
FactoryBakery::Associations.with(mode: :all) { FactoryBakery.bake!(User) }
# => PG::NotNullViolation: null value in column "user_id" of relation "uploads"
```

An optional upload edge is inserted before the user row. Models that need a
persisted `User` as an FK-presence parent fail either on that insert or with
`Primary email can't be blank`. The exact path for the second error is not
isolated yet. **This is the top remaining defect.** Pass D avoids it by reusing
an existing user, and the definitions round avoids it by declaring `User`.

### 5.2 NOT NULL on a fresh parent (A/C)

| Rows | Column | Pass | Example models |
|---:|---|---|---|
| 29 | `uploads.user_id` | C | `AiAgentMcpServer`, `AiTool`, `Category` (same root as §5.1) |
| 27 | `mcp_oauth_authorizations.mcp_oauth_client_id` | C (defined) | |
| 6 | `discourse_kanban_boards.require_confirmation` | A, C | `Boards::BoardHistory`, `Boards::Card`, `Boards::CardHistory` |
| 2 | `discourse_workflows_workflows.created_by_id` | C | `DiscourseWorkflows::WorkflowVersion` |

`require_confirmation` is a NOT NULL boolean with no default that a
FK-presence parent insert leaves nil. That should be fillable generically.

### 5.3 Random or database-dependent (not gem regressions)

Each was probed 3–4 times at both `af756ed` and `e207d72`:

| Model | Behaviour |
|---|---|
| `LlmModel`, `LlmCreditAllocation`, `LlmFeatureCreditCost` | the random provider (`aws_bedrock`, `google_vertex_ai`) requires a `region` key inside `provider_params` jsonb. Fails at random at both snapshots |
| `EmbeddingDefinition` (B) | same provider rule, failed 1 in 3 at both snapshots |
| `AiMcpServer` | "Url must resolve to a publicly accessible address" (DNS), valid 3/3 in probes at both snapshots |
| `RateLimiter::LimitExceeded` (8–11 models, A) | Discourse's rate limiter in development fills up as the run goes on |

### 5.4 Other app-specific clusters

| Rows | Error |
|---:|---|
| 12 | `TypeError: no implicit conversion of String into Integer` (ABCD) |
| 5–9 | `Topic can't be blank, User can't be blank` (A/C) |
| 4 each | `Web hook event types can't be blank`, `Redirect uris is invalid`, `Watched words can't be empty`, `Setting name is not included in the list; Cooked must be blank` |
