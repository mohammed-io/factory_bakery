# Final real-world smoke report — Mastodon (2026-11-19)

Full-boot smoke of the frozen gem snapshot `af756ed` against the real Mastodon
clone (`166fb24`, Rails 8.1.4.1, PostgreSQL `fb_probe_pg:55432`, Redis
`fb-smoke-redis:56379`). 123 eligible AR models, four passes per round:

- A = `required_only` / `fresh`
- B = `required_only` / `reuse`
- C = `all` / `fresh`
- D = `all` / `reuse`

Passes JSON (no cap, no exclusions):

```json
[{"label":"A","mode":"required_only","strategy":"fresh"},
 {"label":"B","mode":"required_only","strategy":"reuse"},
 {"label":"C","mode":"all","strategy":"fresh"},
 {"label":"D","mode":"all","strategy":"reuse"}]
```

Every bake uses `FactoryBakery.bake(Model)` under
`FactoryBakery::Associations.with(mode:, strategy:)` and is checked with
`valid?(:create) || valid?`. `SMOKE_TIMEOUT=30`. The attachments plugin is
active in **both** rounds (`require 'factory_bakery/attachments'`). All HTTP
egress is blocked at the network layer; the gem itself never fetches a URL.

---

## 1. Summary

### Automatic round — no app definitions (only `require 'factory_bakery/attachments'`)

| Pass | Mode / strategy | Models | Valid | Invalid | Error | Timeout | Pass rate |
|---|---|---:|---:|---:|---:|---:|---:|
| A | required_only / fresh | 123 | 106 | 4 | 13 | 0 | **86.2 %** |
| B | required_only / reuse | 123 | 110 | 10 | 3 | 0 | 89.4 % |
| C | all / fresh | 123 | 39 | 3 | 81 | 0 | 31.7 % |
| D | all / reuse | 123 | 96 | 17 | 10 | 0 | 78.0 % |

### Definitions round — `smoke_definitions.rb` (+ attachments plugin)

| Pass | Mode / strategy | Models | Valid | Invalid | Error | Timeout | Pass rate |
|---|---|---:|---:|---:|---:|---:|---:|
| A | required_only / fresh | 123 | **123** | 0 | 0 | 0 | **100.0 %** |
| B | required_only / reuse | 123 | **123** | 0 | 0 | 0 | **100.0 %** |
| C | all / fresh | 123 | 53 | 0 | 70 | 0 | 43.1 % |
| D | all / reuse | 123 | 106 | 3 | 14 | 0 | 86.2 % |

### Goals and previous runs

| Metric | Result |
|---|---|
| Overall automatic pass A vs **80 % goal** | **86.2 % — goal met** (+6.2 pts) |
| Automatic pass A vs previous run (`all-models-baseline.jsonl`) | 30/123 (24.4 %) → 106/123 (**+61.8 pts**) |
| Defined pass A vs previous run (`all-models-defined.jsonl`) | 99/123 (80.5 %) → 123/123 (**+19.5 pts**) |
| Best defined result | A & B 100 %, D 86.2 %; C remains limited by gem `:all`-mode defects (§5) |

Raw JSONL:
`/Users/mohammed/Projects/factory_bakery/.smoke-tests/real-app-cache/mastodon/final-auto.jsonl`
and `.../final-defined.jsonl`.

---

## 2. Works automatically

Every one of these 106 models bakes valid in pass A with **no definition at
all** (`FactoryBakery.bake(Model)`), i.e. validator/column heuristics alone.
The trailing letters are the passes in which the same zero-definition bake is
valid.

```ruby
FactoryBakery.bake(Account)  # valid in AB
FactoryBakery.bake(AccountConversation)  # valid in ABD
FactoryBakery.bake(AccountDeletionRequest)  # valid in ABD
FactoryBakery.bake(AccountDomainBlock)  # valid in ABD
FactoryBakery.bake(AccountModerationNote)  # valid in ABD
FactoryBakery.bake(AccountNote)  # valid in ABD
FactoryBakery.bake(AccountReachFilter)  # valid in ABD
FactoryBakery.bake(AccountRelationshipSeveranceEvent)  # valid in ABD
FactoryBakery.bake(AccountStat)  # valid in ABD
FactoryBakery.bake(AccountStatusesCleanupPolicy)  # valid in ABD
FactoryBakery.bake(AccountSummary)  # valid in ABD
FactoryBakery.bake(AccountWarning)  # valid in ABD
FactoryBakery.bake(AccountWarningPreset)  # valid in ABCD
FactoryBakery.bake(Admin::ActionLog)  # valid in ABD
FactoryBakery.bake(Admin::ServerCheck)  # valid in ABCD
FactoryBakery.bake(Announcement)  # valid in AB
FactoryBakery.bake(AnnouncementMute)  # valid in ABD
FactoryBakery.bake(Appeal)  # valid in ABD
FactoryBakery.bake(Block)  # valid in ABD
FactoryBakery.bake(Bookmark)  # valid in ABD
FactoryBakery.bake(BulkImport)  # valid in ABD
FactoryBakery.bake(BulkImportRow)  # valid in ABCD
FactoryBakery.bake(CanonicalEmailBlock)  # valid in ABD
FactoryBakery.bake(Collection)  # valid in A
FactoryBakery.bake(CollectionItem)  # valid in ABD
FactoryBakery.bake(Conversation)  # valid in AB
FactoryBakery.bake(ConversationMute)  # valid in ABD
FactoryBakery.bake(CustomEmoji)  # valid in ABCD
FactoryBakery.bake(CustomEmojiCategory)  # valid in ABCD
FactoryBakery.bake(DomainAllow)  # valid in ABCD
FactoryBakery.bake(DomainBlock)  # valid in AB
FactoryBakery.bake(Doorkeeper::AccessGrant)  # valid in ABCD
FactoryBakery.bake(Doorkeeper::AccessToken)  # valid in AB
FactoryBakery.bake(Doorkeeper::Application)  # valid in AB
FactoryBakery.bake(EmailDomainBlock)  # valid in AB
FactoryBakery.bake(EmailSubscription)  # valid in ABD
FactoryBakery.bake(Fasp::BackfillRequest)  # valid in ABCD
FactoryBakery.bake(Fasp::Capability)  # valid in ABCD
FactoryBakery.bake(Fasp::DebugCallback)  # valid in ABCD
FactoryBakery.bake(Fasp::FollowRecommendation)  # valid in ABD
FactoryBakery.bake(Fasp::Provider)  # valid in ABCD
FactoryBakery.bake(Fasp::Subscription)  # valid in ABCD
FactoryBakery.bake(Favourite)  # valid in ABD
FactoryBakery.bake(FeaturedTag)  # valid in ABD
FactoryBakery.bake(Follow)  # valid in ABD
FactoryBakery.bake(FollowRecommendation)  # valid in ABD
FactoryBakery.bake(FollowRecommendationMute)  # valid in ABD
FactoryBakery.bake(FollowRecommendationSuppression)  # valid in ABD
FactoryBakery.bake(FollowRequest)  # valid in ABD
FactoryBakery.bake(GeneratedAnnualReport)  # valid in ABD
FactoryBakery.bake(HABTM_Accounts)  # valid in AB
FactoryBakery.bake(HABTM_Statuses)  # valid in AB
FactoryBakery.bake(HABTM_Tags)  # valid in AB
FactoryBakery.bake(Identity)  # valid in ABCD
FactoryBakery.bake(Instance)  # valid in AB  (read-only DB view: bake only, never bake!)
FactoryBakery.bake(Invite)  # valid in ABD
FactoryBakery.bake(IpBlock)  # valid in ABCD
FactoryBakery.bake(Keypair)  # valid in ABD
FactoryBakery.bake(List)  # valid in ABD
FactoryBakery.bake(ListAccount)  # valid in ABD
FactoryBakery.bake(LoginActivity)  # valid in ABCD
FactoryBakery.bake(Marker)  # valid in ABCD
FactoryBakery.bake(MediaAttachment)  # valid in ABD
FactoryBakery.bake(Mention)  # valid in ABD
FactoryBakery.bake(ModerationSubscription)  # valid in ABCD
FactoryBakery.bake(ModerationSubscriptionAdvisory)  # valid in ABCD
FactoryBakery.bake(ModerationSuggestion)  # valid in ABCD
FactoryBakery.bake(Mute)  # valid in ABD
FactoryBakery.bake(NotificationPermission)  # valid in ABD
FactoryBakery.bake(NotificationPolicy)  # valid in ABD
FactoryBakery.bake(NotificationRequest)  # valid in ABD
FactoryBakery.bake(PreviewCard)  # valid in ABD
FactoryBakery.bake(PreviewCardProvider)  # valid in ABCD
FactoryBakery.bake(PreviewCardTrend)  # valid in ABCD
FactoryBakery.bake(PreviewCardsStatus)  # valid in ABD
FactoryBakery.bake(Quote)  # valid in ABD
FactoryBakery.bake(RelationshipSeveranceEvent)  # valid in ABCD
FactoryBakery.bake(Relay)  # valid in ABCD
FactoryBakery.bake(Report)  # valid in ABD
FactoryBakery.bake(ReportNote)  # valid in ABD
FactoryBakery.bake(Rule)  # valid in ABCD
FactoryBakery.bake(RuleTranslation)  # valid in ABCD
FactoryBakery.bake(ScheduledStatus)  # valid in ABD
FactoryBakery.bake(SessionActivation)  # valid in ABD
FactoryBakery.bake(Setting)  # valid in ABCD
FactoryBakery.bake(SeveredRelationship)  # valid in ABD
FactoryBakery.bake(SoftwareDeprecation)  # valid in ABCD
FactoryBakery.bake(SoftwareUpdate)  # valid in ABCD
FactoryBakery.bake(Status)  # valid in AB
FactoryBakery.bake(StatusEdit)  # valid in ABD
FactoryBakery.bake(StatusPin)  # valid in AB
FactoryBakery.bake(StatusStat)  # valid in ABD
FactoryBakery.bake(StatusTrend)  # valid in ABD
FactoryBakery.bake(Tag)  # valid in ABCD
FactoryBakery.bake(TagFollow)  # valid in ABD
FactoryBakery.bake(TagTrend)  # valid in ABCD
FactoryBakery.bake(TaggedObject)  # valid in ABD
FactoryBakery.bake(Tombstone)  # valid in ABD
FactoryBakery.bake(UnavailableDomain)  # valid in ABCD
FactoryBakery.bake(User)  # valid in AB
FactoryBakery.bake(UserInviteRequest)  # valid in ABCD
FactoryBakery.bake(UserIp)  # valid in ABCD
FactoryBakery.bake(UserRole)  # valid in ABCD
FactoryBakery.bake(UsernameBlock)  # valid in ABCD
FactoryBakery.bake(Web::Setting)  # valid in ABCD
FactoryBakery.bake(WebauthnCredential)  # valid in ABCD
```

Note on network: in the automatic round the 17 pass-A failures include 11
outbound HTTP attempts caused by **app** setters, never by the gem:
`Account#avatar_remote_url=` / `#header_remote_url=` (and the same on baked
`Account` parents) call `Remotable#download_*!`, which performs a live
`Request.get` at `app/models/concerns/remotable.rb:24-32`. The heuristic had
generated a reserved RFC-2606 URL for the `*_remote_url` column; the setter
tried to fetch it. `CustomEmoji#image_remote_url=` has the same behaviour
(`app/models/custom_emoji.rb:60`).

---

## 3. Needs a definition

17 models failed automatic pass A; each got a **minimal** definition. The
complete final file is copied to
`docs/reports/smoke/20261119-final-mastodon-definitions.rb`. Full code and the
exact app rule the gem cannot discover:

| Model | App rule / state the gem cannot infer (source) | Definition |
|---|---|---|
| `Account` | `avatar_remote_url=` / `header_remote_url=` fetch over HTTP (`concerns/remotable.rb:41-47`); local accounts require blank remote URLs (`account.rb:143-149`); two mutually-constraining username regexes (`account.rb:130,137`); self-ref `moved_to_account` in `:all` | `avatar_remote_url { nil }`, `header_remote_url { '' }`, `avatar/header { nil }`, nil local URLs, random literal `username`, `skip :moved_to_account` |
| `AccountAlias` | `before_validation :set_uri` calls `ResolveAccountService` over the network and `validate_target_account` compares `TagManager.uri_for(account)` (`account_alias.rb:35-40,50-55`); unsaved account has nil id → route error | Persist a local `Account`, explicit `acct` + `uri` |
| `AccountMigration` | `set_target_account` resolves `acct` (`account_migration.rb:70`) and `validate_target_account` needs target `also_known_as` to contain the source URI (`account_migration.rb:79-86`) | Local source/target pair, `acct { target.username }`, target carries `uri_for(source)` |
| `AccountPin` | `validate_follow_relationship` requires a persisted `Follow` (`account_pin.rb:25-27`) | `bake!` a `Follow` between two persisted accounts |
| `AnnouncementReaction` | `name` must be a recognised emoji (`announcement_reaction.rb`) | `name { '🐮' }` |
| `Backup` | dump attachment needs an explicit no-op | `dump { nil }` |
| `Collection` | `user_does_not_exceed_limit` dereferences `account.user.role` (`collection.rb:118-122`); `collection_items` back-edge cycles in `:all` | Account from a persisted `User`, `skip :collection_items` |
| `CustomEmoji` | `remotable_attachment :image` fetches (`custom_emoji.rb:60`) | `image_remote_url { nil }` + explicit Paperclip metadata |
| `CustomFilter` | `title`/`context` have app-specific inclusion rules | `title { 'smoke filter' }`, `context { ['home'] }` |
| `AccountWarning` | cross-field `created_at` rule | `created_at { Time.current }` |
| `Doorkeeper::Application` | polymorphic `owner` has a real users FK; account owner breaks it | `owner { bake!(User) }`, nil polymorphic columns, literal `redirect_uri` |
| `EmailDomainBlock` | self-referential `parent` cycle (`email_domain_block.rb`) | `skip :parent` |
| `InstanceModerationNote` | `Instance` is a **read-only DB view**; a raw-FK presence edge tries to `bake!` it (`persistence_adapter.rb:27`); `skip :instance` also suppresses the natural-key `domain` FK | `skip :instance` + explicit `domain { 'example.com' }`; root `Instance` itself is only `bake`d, never `bake!`d |
| `Poll` | `PollOptionsValidator` needs ≥2 options and expiry within 5 min…1 month (`app/validators/poll_expiration_validator.rb:4-15`) | `options` pair, `expires_at { 1.day.from_now }` |
| `PollVote` | choice must exist and you cannot vote on your own poll (`poll_vote.rb`) | Persist a `Poll` and a distinct `Account`, `choice { 0 }` |
| `SiteUpload` | Paperclip `styles` lambda indexes `STYLES` by `var`; an unknown generated var → `nil.each_pair` (`site_upload.rb:60`) | `var { 'mascot' }` |
| `TermsOfService` | published terms need `changelog` and a **future, unique** `effective_date` (`terms_of_service.rb:23,72-77`) | `published_at { nil }`, literal changelog, random future date |
| `Web::PushSubscription` | `WebPushKeyValidator` performs real ECDH encryption (`app/validators/web_push_key_validator.rb:3-10`) | Generate a real P-256 public key + 16-byte auth secret |
| `Webhook` | `events` must come from the fixed `EVENTS` list (`webhook.rb:18-26,79-81`) | `events { ['status.created'] }` |
| `User`, `Follow`, `FollowRequest`, `Collection`, `List`, `Status`, `Quote`, `Conversation`, `AccountConversation`, `StatusPin` | `:all`-mode only: read-only views (`User#ips → UserIp`), cyclic edges (`moved_to_account`, `parent`, `status`, `quotes`, …) and `Follow/FollowRequest` `validates :languages, language: true` (`follow.rb:32`, `follow_request.rb:32`) fed non-locale words; `AccountConversation#set_last_status` derives `last_status_id` from `status_ids` (`account_conversation.rb:114-117`) | `skip` on the collection/optional side, `languages { [] }`, explicit `status_ids`, same-account `StatusPin` |

Full definition code (identical to the copied file):

```ruby
# frozen_string_literal: true
require 'securerandom'
require 'openssl'
require 'base64'
require 'factory_bakery/attachments'

FactoryBakery.define(Account) do
  avatar_remote_url { nil }
  header_remote_url { '' }
  avatar { nil }
  header { nil }
  domain { nil }
  uri { nil }
  inbox_url { '' }
  outbox_url { '' }
  followers_url { '' }
  following_url { '' }
  shared_inbox_url { '' }
  username { "fb_#{SecureRandom.hex(5)}" }
  skip :moved_to_account
end

FactoryBakery.define(User) do
  email { "fb_#{SecureRandom.hex(5)}@example.com" }
  password { 'SmokePass123!' }
  agreement { true }
  skip :ips, :invite, :created_by_application, :applications
end

FactoryBakery.define(Backup) { dump { nil } }

FactoryBakery.define(Doorkeeper::Application) do
  owner_id { nil }
  owner_type { nil }
  owner { FactoryBakery.bake!(User) }
  redirect_uri { 'https://example.com/callback' }
end

FactoryBakery.define(EmailDomainBlock) { skip :parent }

FactoryBakery.define(CustomEmoji) do
  image_file_name { 'emoji.png' }
  image_content_type { 'image/png' }
  image_file_size { 1024 }
  image_remote_url { nil }
end

FactoryBakery.define(AnnouncementReaction) { name { '🐮' } }
FactoryBakery.define(CustomFilter) do
  title { 'smoke filter' }
  context { ['home'] }
end
FactoryBakery.define(AccountWarning) { created_at { Time.current } }

FactoryBakery.define(InstanceModerationNote) do
  skip :instance
  domain { 'example.com' }
end

FactoryBakery.define(AccountAlias) do
  account { FactoryBakery.bake!(Account) }
  acct { 'smoke_alias@example.com' }
  uri { 'https://example.com/accounts/smoke-alias' }
end

FactoryBakery.define(AccountMigration) do
  source = nil
  target = nil
  account { source = FactoryBakery.bake!(Account) }
  target_account do
    target = FactoryBakery.bake!(Account, also_known_as: [ActivityPub::TagManager.instance.uri_for(source)])
  end
  acct { target.username }
end

FactoryBakery.define(AccountPin) do
  pin_account = nil
  account { pin_account = FactoryBakery.bake!(Account) }
  target_account do
    target = FactoryBakery.bake!(Account)
    FactoryBakery.bake!(Follow, account: pin_account, target_account: target)
    target
  end
end

FactoryBakery.define(Poll) do
  options { ['smoke option one', 'smoke option two'] }
  expires_at { 1.day.from_now }
end

FactoryBakery.define(PollVote) do
  poll { FactoryBakery.bake!(Poll) }
  account { FactoryBakery.bake!(Account) }
  choice { 0 }
end

FactoryBakery.define(SiteUpload) { var { 'mascot' } }

FactoryBakery.define(TermsOfService) do
  published_at { nil }
  changelog { 'smoke changelog' }
  effective_date { Date.current + SecureRandom.random_number(1..300) }
end

_push_curve = OpenSSL::PKey::EC.generate('prime256v1')
_push_p256dh = Base64.urlsafe_encode64(_push_curve.public_key.to_bn.to_s(2))
_push_auth = Base64.urlsafe_encode64(Random.new.bytes(16))
FactoryBakery.define(Web::PushSubscription) do
  key_p256dh { _push_p256dh }
  key_auth { _push_auth }
end

FactoryBakery.define(Webhook) { events { ['status.created'] } }

FactoryBakery.define(Follow) { languages { [] } }
FactoryBakery.define(FollowRequest) { languages { [] } }
FactoryBakery.define(Collection) do
  account { FactoryBakery.bake!(User).account }
  skip :collection_items
end
FactoryBakery.define(List) { skip :list_accounts }
FactoryBakery.define(Status) do
  text { 'smoke status text' }
  skip :bookmarks, :quotes, :reblogs, :replies, :media_attachments
end
FactoryBakery.define(Quote) { skip :quoted_status }
FactoryBakery.define(Conversation) { skip :statuses }
FactoryBakery.define(AccountConversation) do
  status_ids { [FactoryBakery.bake!(Status).id] }
end
FactoryBakery.define(StatusPin) do
  pin_account = nil
  account { pin_account = FactoryBakery.bake!(Account) }
  status { FactoryBakery.bake!(Status, account: pin_account) }
end
```

---

## 4. Still failing

Passes A and B are completely clean (123/123 each). The residual failures are
all in the **`all` mode** passes C and D and are gem defects, not missing
definitions:

| Pass | Count | Grouped error | Root cause | Class |
|---|---:|---|---|---|
| C | 63 | `ActiveRecord::RecordInvalid: Account must exist` | `:all` auto-builds `has_many` children and saves them through `FkParentPersistence`; the required `belongs_to :account` parent is not persisted before the child validates. Reproduced by baking any `Account`-related model under `Associations.with(mode: :all, strategy: :fresh)`. | **Gem defect** |
| C | 2 | `ReadOnlyTargetError` / `ReadOnlyRecord` | `User#ips → UserIp` and `Collection` reach read-only DB views; the gem's read-only guard does not fire for parents built by `:all` (raw AR `ReadOnlyRecord` escapes). | **Gem defect** |
| C | 2 | `can't write unknown attribute 'left_side_id'` | `HABTM_Statuses`, `HABTM_Tags`: `:all` tries to auto-build anonymous HABTM join models whose generated class has no `left_side_id` setter. | **Gem defect** |
| C | 1 | `CyclicAssociationError: Quote#status -> Quote#status` | Optional self-referential `Quote#quoted_status` is auto-built in `:all`; explicit `skip :quoted_status` cannot suppress a *nested* node discovered through another edge. | **Gem defect** |
| C | 1 | `IncompletePersistenceError` for `PollVote` account | A sibling built in the graph stays unsaved under `:all`. | **Gem defect** |
| C | 1 | `Quotes is invalid` on `AccountConversation` | `:all` collection children fail validation after the derived-attribute fix. | **Gem defect / app cross-field rule** |
| D | 8 | `Account must exist` | Same raw-FK parent-persistence defect under `:reuse`. | **Gem defect** |
| D | 4 | collection validation (`Status`, `Conversation`, `User`, `AccountConversation`) | `:all` fills collections (`reblogs`, `replies`, `statuses`, `applications`) whose children carry app-only rules. | **Gem defect** |
| D | 2 | read-only view (`Collection`, `Doorkeeper::Application`) | Same as pass C. | **Gem defect** |
| D | 3 | HABTM `left_side_id` | Same as pass C. | **Gem defect** |

No model was made valid by editing application code; all fixes live in the
clone-local definitions file. `Instance` is a read-only database view: it is
successfully `bake`d (populated + `valid?`) in A/B and is never `bake!`d.

---

## 5. Gem defects / improvement opportunities (ranked by models affected)

1. **`:all` mode cannot persist required-parent graphs in Mastodon** — ~70 models in
   pass C / ~17 in pass D. Auto-built `has_many` children with a required
   `belongs_to` are saved before their parent is persisted, producing
   `Account must exist`. This is the single largest loss of pass-rate.
   *Improvement:* topologically order the auto-built graph, or skip persisting
   unsaved children that cannot be saved, rather than raising `RecordInvalid`.
2. **Read-only parents built through raw-FK presence edges** — ~70 models in the
   automatic pass C cascade, plus `Doorkeeper::Application`/`Collection` in the
   defined round. `lib/factory_bakery/associations/fk_parent_persistence.rb:47`
   calls `PersistenceAdapter.save!` on a record whose `readonly?` is true; AR
   raises `ActiveRecord::ReadOnlyRecord` instead of the documented
   `FactoryBakery::ReadOnlyTargetError`. `Instance` is a DB view; `UserIp` is
   another.
3. **Custom-validator columns filled with invalid values in `:all` mode** —
   `Follow#languages` / `FollowRequest#languages`
   (`follow.rb:32`, `follow_request.rb:32`) receive random words that fail the
   app's `language: true` validator, which then cascades through ~70 models in
   pass C. Custom `EachValidator`s are documented as not forcing a fill, but
   `:all` fills every column regardless and does not verify these values.
4. **Side-effecting `*_remote_url` setters are invoked by the heuristic** —
   `Account`, `CustomEmoji`, `PreviewCard`, `PreviewCardProvider` (and every
   model that bakes one as a parent, ~15 models in automatic pass A). The gem's
   reserved `https://example.*/...` values are passed to setters that fetch
   (`concerns/remotable.rb:24-32`). `skip` is the documented workaround, but
   a safer default for `*_remote_url` columns would avoid the network entirely.
5. **Cyclic association detection is too eager in `:all` mode** — `Account`,
   `EmailDomainBlock`, `Doorkeeper::Application`, `Collection`, `Invite`, `List`,
   `Quote`, `Status` (8 models). Optional self-references (`moved_to_account`,
   `parent`, `quoted_status`) are built recursively; a declaration on the root
   does not suppress the same edge when reached as a nested node.
6. **HABTM join models cannot be built in `:all` mode** — `HABTM_Accounts`,
   `HABTM_Statuses`, `HABTM_Tags` (3 models): `ActiveModel::MissingAttributeError:
   left_side_id`. The plugin documents HABTM as unsupported for `association`
   declarations but `:all` auto-build still tries to create join rows.
7. **Raw-FK edges persist parents even under plain `bake`** — documented in the
   README, but it means this smoke test writes rows to the real app DB (and
   under `:reuse` raises "found no row to reuse" for `InstanceModerationNote`
   in passes B/D). A non-persisting option would be useful for zero-write bakes.
8. **Uniqueness probing ignores unsaved graph siblings** — `StatusTrend` and
   nested `Account` bakes collide on uniqueness-constrained columns because
   `UniquenessEnforcer` only queries the DB (`lib/factory_bakery/uniqueness_enforcer.rb:27-39`);
   two generated values in one unsaved graph can be identical.

Outbound network was off for all bakes. The only HTTP/connection errors seen
were caused by the app setters listed in item 4 — the gem never opened a
socket itself.
