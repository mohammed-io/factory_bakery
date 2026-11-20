# Real-world smoke report after the defect fixes — Mastodon (2026-11-20)

Full-boot rerun of every Mastodon model after the ten smoke-found defects
from [the 2026-11-19 run](20261119-final-mastodon.md) were fixed. Same app
clone (`166fb24`, Rails 8.1.4.1), same PostgreSQL (`fb_probe_pg:55432`) and
Redis (`fb-smoke-redis:56379`), same runner, same definitions file
([`20261119-final-mastodon-definitions.rb`](20261119-final-mastodon-definitions.rb)),
same `SMOKE_TIMEOUT=30`. Only the gem changed:

| | Gem snapshot |
|---|---|
| 2026-11-19 (before) | `af756ed` |
| 2026-11-20 (this run) | `e207d72` (`mohd/v0.0.2`) |

123 eligible AR models, four passes per round:

```json
[{"label":"A","mode":"required_only","strategy":"fresh"},
 {"label":"B","mode":"required_only","strategy":"reuse"},
 {"label":"C","mode":"all","strategy":"fresh"},
 {"label":"D","mode":"all","strategy":"reuse"}]
```

Each bake is `FactoryBakery.bake(Model)` inside
`FactoryBakery::Associations.with(mode:, strategy:)`, checked with
`valid?(:create) || valid?`. The attachments plugin is active in both rounds.

---

## 1. Summary

### Automatic round: no app definitions (only `require 'factory_bakery/attachments'`)

| Pass | Mode / strategy | Models | Valid | Invalid | Error | Timeout | Pass rate | 2026-11-19 valid | Δ |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| A | required_only / fresh | 123 | **112** | 9 | 2 | 0 | **91.1 %** | 106 | +6 |
| B | required_only / reuse | 123 | **110** | 12 | 1 | 0 | 89.4 % | 110 | +0 |
| C | all / fresh | 123 | **111** | 10 | 2 | 0 | **90.2 %** | 39 | **+72** |
| D | all / reuse | 123 | **110** | 12 | 1 | 0 | 89.4 % | 96 | +14 |

### Definitions round: `20261119-final-mastodon-definitions.rb` plus the attachments plugin

| Pass | Mode / strategy | Models | Valid | Invalid | Error | Timeout | Pass rate | 2026-11-19 valid | Δ |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|
| A | required_only / fresh | 123 | **123** | 0 | 0 | 0 | **100.0 %** | 123 | +0 |
| B | required_only / reuse | 123 | **121** | 2 | 0 | 0 | 98.4 % | 123 | −2 |
| C | all / fresh | 123 | **113** | 1 | 8 | 1 | **91.9 %** | 53 | **+60** |
| D | all / reuse | 123 | **113** | 2 | 8 | 0 | 91.9 % | 106 | +7 |

### Headline

- `:all` no longer collapses. Automatic pass C went from 31.7 % to 90.2 %, and
  the definitions round from 43.1 % to 91.9 %. Before, one failing optional edge
  (a cycle, a read-only view, a HABTM join, a `has_many` without a verified
  inverse) failed the whole bake. Now each optional edge is built in its own
  savepoint and dropped if it fails.
- Automatic pass A is at 91.1 %, against the 80 % goal (+11.1 pts).
- With definitions, required-only pass A is still 100 %.
- The only drops are four `:reuse` models (B/D): Appeal, ListAccount, StatusPin
  and AccountConversation. **They are not caused by the gem change.** At the old
  snapshot `af756ed`, against today's database, they fail the same way (§5.1).
  Every bake in earlier runs left rows behind, so `:reuse` now picks different
  existing rows than it did on 2026-11-19.

Raw JSONL:
`/Users/mohammed/Projects/factory_bakery/.smoke-tests/real-app-cache/mastodon/fix3-auto.jsonl`
and `…/fix3-defined.jsonl` (2026-11-19 baseline: `final-auto.jsonl`,
`final-defined.jsonl`).

---

## 2. What was fixed, with code

Every fix has specs in the gem suite: **1208 examples, 0 failures, 8 pending**
(the pending ones are PostgreSQL-only), with 100 % line and branch coverage.
The Mastodon models each fix unblocked are listed with it.

### 2.1 In-graph identity: reuse what this bake already built

You asked for this one directly. With `strategy: :fresh`, an auto-built
`belongs_to` now reuses a finished object of exactly the target class built
earlier in the same bake, instead of creating a second copy.

```ruby
# lib/factory_bakery/associations/belongs_to_builder.rb
def build_parent(klass, entry, siblings = [])
  completed = completed_parent(klass, entry, siblings)
  return completed if completed
  return build_optional_parent(klass, entry) if optional_edge?(entry)

  build_required_parent(klass, entry)
end

def completed_parent(klass, entry, siblings)
  return nil if entry.polymorphic
  return nil unless ReuseResolver.strategy_for(nil) == :fresh
  return nil if entry.scope
  return nil if uniqueness_validated_fk?(klass, entry)

  shareable(BuildContext.completed_object_of(entry.resolve_target, exclude: siblings), entry)
end

# Under bake! (and on raw-FK-presence edges) only a persisted object is shared.
def shareable(object, entry)
  return nil unless object
  return object unless entry.fk_presence || BuildContext.persisting?

  object.respond_to?(:persisted?) && object.persisted? ? object : nil
end
```

Guard rails, each backed by a spec:

| Not shared when… | Why |
|---|---|
| the edge is polymorphic or scoped | the target class or row set is not fixed |
| the FK is uniqueness-validated or uniquely indexed | two owners would collide |
| the object already fills a sibling edge of the same owner | `Transfer#sender` ≠ `Transfer#receiver` (`order.buyer` ≠ `order.seller`) |
| the object is an ancestor on the current build path | that would close a cycle |
| the edge is raw-FK-presence, or the bake is `bake!`, and the object is unsaved | an unsaved parent shared into an insert graph can close an autosave cycle and insert a nil FK (Mastodon `PollVote` → `Poll` → `Account`) |

```ruby
# Effect in Mastodon (required_only / fresh):
status = FactoryBakery.bake(StatusPin)
status.account.equal?(status.status.account) # => true, one Account, not two
```

### 2.2 Read-only models are never saved, not even by `bake!`

```ruby
# lib/factory_bakery/associations/fk_parent_persistence.rb (shape)
def settle(parent, entry)
  return adopt(parent) if read_only_new?(parent) && (required?(entry) || BuildContext.persisting?)

  persist_fk!(parent, entry)   # saves only new, writable parents on FK-presence edges
end

# A read-only parent (a DB view such as Mastodon's Instance / UserIp) adopts
# an existing row instead (`klass.reorder(pk).first`), else stays unsaved.
```

```ruby
FactoryBakery.bake(InstanceModerationNote)   # valid in ABCD, no definition
                                             # (2026-11-19 A: ReadOnlyRecord: Instance is marked as readonly)
FactoryBakery.bake(Instance)                 # valid in ABCD (the view is baked, never inserted)
```

A `:reuse` miss now falls back to a fresh build. Before, it raised.

### 2.3 Bounded `:all`

```ruby
# lib/factory_bakery/associations/all_auto_builder.rb
def build_optional_child(object, entry, declaration)
  adapter = FactoryBakery::MapperRegistry.persistence_adapter(object.class)
  mark = BuildContext.generated_records.length
  begin
    if adapter.transactional?
      adapter.transaction(object.class) { build_and_validate(object, entry, declaration) }
    else
      build_and_validate(object, entry, declaration)
    end
  rescue StandardError
    BuildContext.trim_generated_records!(mark)
    discard_child(object, entry)   # nil / empty collection
  end
end
```

- Optional `belongs_to` / `has_one` / `has_many` edges are built in a savepoint
  and discarded if they raise or are invalid.
- `CyclicAssociationError` is raised only for required edges.
- HABTM join models are skipped, and a HABTM `left_side` reports its real join FK.
- A `has_many` with no verified inverse, whose child has a required
  `belongs_to` back to the owner, is skipped. This used to fail with
  "Owner must exist".

```ruby
FactoryBakery::Associations.with(mode: :all) do
  FactoryBakery.bake(User)            # was ActiveRecord::ReadOnlyRecord: Instance is marked as readonly
  FactoryBakery.bake(Follow)          # same; the read-only Instance view is now adopted, never saved
  FactoryBakery.bake(Status)          # was HTTP::ConnectionError from an optional edge's remote_url fill (§2.4)
  FactoryBakery.bake(HABTM_Tags)      # was a 404 from the same remote_url fetch
end
```

In the 2026-11-19 pass C, 81 errors came from three sources: optional edges
pulling in the read-only `Instance` view, `*_remote_url` fills that fetched
over HTTP, and cycles. §2.2–2.4 fix each one.

Pass C newly valid (72 models, automatic round): `Account`, `AccountAlias`,
`AccountDeletionRequest`, `AccountDomainBlock`, `AccountModerationNote`,
`AccountNote`, `AccountReachFilter`, `AccountRelationshipSeveranceEvent`,
`AccountStat`, `AccountStatusesCleanupPolicy`, `AccountSummary`,
`AccountWarning`, `Admin::ActionLog`, `Announcement`, `AnnouncementMute`,
`Appeal`, `Block`, `Bookmark`, `BulkImport`, `CanonicalEmailBlock`,
`Collection`, `CollectionItem`, `Conversation`, `ConversationMute`,
`CustomFilterKeyword`, `CustomFilterStatus`, `DomainBlock`,
`Doorkeeper::AccessToken`, `Doorkeeper::Application`, `EmailDomainBlock`,
`EmailSubscription`, `Fasp::FollowRecommendation`, `Favourite`, `Follow`,
`FollowRecommendation`, `FollowRecommendationMute`,
`FollowRecommendationSuppression`, `FollowRequest`, `GeneratedAnnualReport`,
`HABTM_Accounts`, `HABTM_Statuses`, `HABTM_Tags`, `Instance`,
`InstanceModerationNote`, `Invite`, `Keypair`, `List`, `MediaAttachment`,
`Mention`, `Mute`, `Notification`, `NotificationPermission`,
`NotificationPolicy`, `NotificationRequest`, `PollVote`, `PreviewCard`,
`PreviewCardsStatus`, `Quote`, `Report`, `ReportNote`, `ScheduledStatus`,
`SessionActivation`, `SeveredRelationship`, `Status`, `StatusEdit`,
`StatusPin`, `StatusStat`, `StatusTrend`, `TagFollow`, `TaggedObject`,
`Tombstone`, `User`.

### 2.4 Remote-URL setters are never fed a value

```ruby
# lib/factory_bakery/active_record_mapper/constraint_reader.rb
REMOTE_URL_WRITER_PATTERN = /(?:\A|_)remote_url\z|\Aremote_\w*url\z/
```

Mastodon's `Remotable#avatar_remote_url=` downloads whatever it is given. A
`guarded_writer` fact routes such attributes to `GuardedWriterFiller`. They
stay nil or default, or get `''` when the column is NOT NULL without a default.
This applies even with `fill_optional: true`. So `bake(Account)` no longer tries
to fetch a URL.

### 2.5 Uniqueness across the whole graph

```ruby
# one bake, two unsaved siblings, same unique column: no collision
FactoryBakery.bake(Follow)  # account.username and target_account.username differ
```

- A per-bake registry, keyed by table, attribute and normalized value, plus the
  DB check. Case folding applies when the validator is case-insensitive. After
  3 collisions an entropy suffix is added.
- Single-column unique indexes count as uniqueness. A unique-index-only column
  is now also checked against the database.

### 2.6 Smoke regressions found by this rerun and fixed before the final run

| Model | Symptom | Root cause | Fix |
|---|---|---|---|
| `User` (A, B) | "Service agreement must be accepted"; Account got a `domain` and then needed `inbox_url` | (1) `validates :agreement, acceptance:` defines its writer lazily, so the mapper never saw it. (2) The verified-fallback rebuild filled optional columns on nested parents too | acceptance names count as settable; the rebuild opt-in is depth-scoped (`FillOptional.with_rebuild`) |
| `PollVote` (definitions, A) | `PG::NotNullViolation` on `polls.account_id` | under `bake!` an unsaved Account was shared into the insert graph | share only persisted objects under `bake!` |

```ruby
# lib/factory_bakery/fill_optional.rb
def with_rebuild(depth, &block)
  previous = Fiber[REBUILD_DEPTH_KEY]
  Fiber[REBUILD_DEPTH_KEY] = depth
  with(true, &block)
ensure
  Fiber[REBUILD_DEPTH_KEY] = previous
end
```

---

## 3. Works automatically

Valid with **no definition at all** (`FactoryBakery.bake(Model)`, attachments
plugin only). The letters are the passes the model is valid in.

**ABCD (107):** `Account`, `AccountDeletionRequest`, `AccountDomainBlock`,
`AccountModerationNote`, `AccountNote`, `AccountReachFilter`,
`AccountRelationshipSeveranceEvent`, `AccountStat`,
`AccountStatusesCleanupPolicy`, `AccountSummary`, `AccountWarning`,
`AccountWarningPreset`, `Admin::ActionLog`, `Admin::ServerCheck`,
`Announcement`, `AnnouncementMute`, `Backup`, `Block`, `Bookmark`,
`BulkImport`, `BulkImportRow`, `CanonicalEmailBlock`, `Collection`,
`CollectionItem`, `CollectionReport`, `Conversation`, `ConversationMute`,
`CustomEmoji`, `CustomEmojiCategory`, `CustomFilterKeyword`,
`CustomFilterStatus`, `DomainAllow`, `DomainBlock`, `Doorkeeper::AccessGrant`,
`Doorkeeper::AccessToken`, `Doorkeeper::Application`, `EmailDomainBlock`,
`EmailSubscription`, `Fasp::BackfillRequest`, `Fasp::Capability`,
`Fasp::DebugCallback`, `Fasp::FollowRecommendation`, `Fasp::Provider`,
`Fasp::Subscription`, `Favourite`, `Follow`, `FollowRecommendation`,
`FollowRecommendationMute`, `FollowRecommendationSuppression`,
`FollowRequest`, `GeneratedAnnualReport`, `HABTM_Accounts`, `HABTM_Statuses`,
`HABTM_Tags`, `Identity`, `Instance`, `InstanceModerationNote`, `Invite`,
`IpBlock`, `Keypair`, `List`, `LoginActivity`, `Marker`, `MediaAttachment`,
`Mention`, `ModerationSubscription`, `ModerationSubscriptionAdvisory`,
`ModerationSuggestion`, `Mute`, `Notification`, `NotificationPermission`,
`NotificationPolicy`, `NotificationRequest`, `PreviewCard`,
`PreviewCardProvider`, `PreviewCardTrend`, `PreviewCardsStatus`, `Quote`,
`RelationshipSeveranceEvent`, `Relay`, `Report`, `ReportNote`, `Rule`,
`RuleTranslation`, `ScheduledStatus`, `SessionActivation`, `Setting`,
`SeveredRelationship`, `SoftwareDeprecation`, `SoftwareUpdate`, `Status`,
`StatusEdit`, `StatusStat`, `StatusTrend`, `Tag`, `TagFollow`, `TagTrend`,
`TaggedObject`, `Tombstone`, `User`, `UserInviteRequest`, `UserIp`,
`UserRole`, `UsernameBlock`, `Web::Setting`, `WebauthnCredential`

**ABD:** `FeaturedTag` · **BCD:** `AccountAlias`, `PollVote` ·
**AC:** `AccountConversation`, `StatusPin` · **A:** `Appeal`, `ListAccount`

```ruby
require 'factory_bakery/associations'
require 'factory_bakery/attachments'

FactoryBakery.bake(Status)                    # required_only / fresh by default
FactoryBakery::Associations.with(mode: :all) do
  FactoryBakery.bake(Account)                 # every optional edge tried, failures dropped
end
FactoryBakery::Associations.with(strategy: :reuse) do
  FactoryBakery.bake(Favourite)               # reuses existing Account/Status rows
end
```

---

## 4. Needs a definition (unchanged)

These 11 models need app knowledge the gem cannot discover. The definitions
from 2026-11-19 still bring required-only to 123/123:

| Model | Why | Definition |
|---|---|---|
| `AccountAlias`, `AccountMigration` | resolve `acct` over the network / compare `uri_for` | persisted local accounts, explicit `acct` + `uri` |
| `AccountPin` | requires an existing `Follow` | `bake!` a `Follow` first |
| `AnnouncementReaction` | `name` must be a known emoji | `name { '🐮' }` |
| `CustomFilter` | app-specific `context` list | `title { … }`, `context { ['home'] }` |
| `Poll` | ≥2 options, expiry within 5 min…1 month | `options { [...] }`, `expires_at { 1.day.from_now }` |
| `PollVote` | choice must exist, not your own poll | persisted `Poll` + distinct `Account`, `choice { 0 }` |
| `SiteUpload` | Paperclip styles lambda indexes `STYLES[var]` | `var { 'mascot' }` |
| `TermsOfService` | changelog + future unique `effective_date` | literal changelog, future date |
| `Web::PushSubscription` | real ECDH key validation | generated P-256 key + auth secret |
| `Webhook` | `events` from a fixed list | `events { ['status.created'] }` |

```ruby
FactoryBakery.define(PollVote) do
  poll { FactoryBakery.bake!(Poll) }
  account { FactoryBakery.bake!(Account) }
  choice { 0 }
end
```

---

## 5. Still failing and what is next

### 5.1 `:reuse` picks rows that break cross-record rules (B/D, both rounds)

| Model | Error | Cause |
|---|---|---|
| `Appeal` | Account warning has already been taken | reused `AccountWarning` already has an Appeal (unique FK) |
| `ListAccount` | Account must be a followed account | reused `List` owner does not follow the reused `Account` |
| `StatusPin` | Someone else's post cannot be pinned | reused `Status` belongs to another account |
| `AccountConversation` | Last status must exist | derived from `status_ids` |

The same four fail at `af756ed` against today's database
(`PROBE … required_only/reuse valid=false` at both snapshots), so the gem
change did not cause this. **Next improvement:** for a uniquely indexed or
uniqueness-validated FK, `ReuseResolver` should choose a row that is not
already referenced, or build fresh.

### 5.2 Definitions round, `:all` (C/D)

| Cluster | Models | Note |
|---|---|---|
| `IncompletePersistenceError`: the nested `bake!` inside a definition built optional `:all` children (`AccountReachFilter`, `AccountRelationshipSeveranceEvent`, `Collection`, `Follow`) that the outer `bake!` does not persist | `AccountAlias`, `AccountMigration`, `AccountPin`, `PollVote`, `StatusPin` | next defect: optional `:all` children of a nested `bake!` should be persisted with it or not built |
| `ReadOnlyTargetError: User#ips → UserIp` | `Collection`, `Doorkeeper::Application` | under `bake!` an optional collection to a read-only view should be skipped, not raised |
| `AccountConversation` | unique `conversations.parent_status_id` (C), `Reblogs is invalid` (D) | |
| `Instance` | 30 s timeout (C) | |

### 5.3 Automatic round leftovers

`FeaturedTag` (C) hits a NOT NULL on `account_moderation_notes.target_account_id`,
reached through an optional `:all` edge that inserts during the build.
Everything else in §4 is app knowledge.
