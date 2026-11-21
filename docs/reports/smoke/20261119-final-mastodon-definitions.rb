# frozen_string_literal: true

# FactoryBakery custom factories for the real-world full-boot smoke run.
# Real .rb file, require-loaded by the rails runner (SMOKE_DEFINITIONS).
# TEST-ONLY definitions living in the disposable clone, never in the gem.

require 'securerandom'
require 'openssl'
require 'base64'
require 'factory_bakery/attachments'

FactoryBakery.define(Account) do
  # Remotable attachment setters perform a live HTTP fetch (app/models/concerns/remotable.rb).
  avatar_remote_url { nil }
  header_remote_url { '' } # NOT NULL default '' in db/schema.rb; blank skips the fetch
  avatar { nil }
  header { nil }
  # Local accounts avoid the remote-uri/inbox_url requirements. NOT NULL columns
  # in db/schema.rb default to '' so never hand them nil.
  domain { nil }
  uri { nil }
  inbox_url { '' }
  outbox_url { '' }
  followers_url { '' }
  following_url { '' }
  shared_inbox_url { '' }
  # Two mutually-constraining format regexes defeat the synthesizer; a valid literal wins.
  username { "fb_#{SecureRandom.hex(5)}" }
  # :all mode would otherwise recurse Account -> moved_to_account -> Account.
  skip :moved_to_account
end

FactoryBakery.define(User) do
  email { "fb_#{SecureRandom.hex(5)}@example.com" }
  password { 'SmokePass123!' }
  agreement { true }
  # Read-only DB views / self referential edges reached only by :all mode.
  skip :ips, :invite, :created_by_application, :applications
end

FactoryBakery.define(Backup) do
  dump { nil }
end

FactoryBakery.define(Doorkeeper::Application) do
  # Polymorphic owner has a real DB FK to users; an Account breaks that FK.
  owner_id { nil }
  owner_type { nil }
  association :owner, User
  redirect_uri { 'https://example.com/callback' }
end

FactoryBakery.define(EmailDomainBlock) do
  skip :parent # self referential cycle in :all mode
end

FactoryBakery.define(CustomEmoji) do
  image_file_name { 'emoji.png' }
  image_content_type { 'image/png' }
  image_file_size { 1024 }
  image_remote_url { nil } # remotable_attachment setter would fetch (custom_emoji.rb:60)
end

FactoryBakery.define(AnnouncementReaction) do
  name { '🐮' }
end

FactoryBakery.define(CustomFilter) do
  title { 'smoke filter' }
  context { ['home'] }
end

FactoryBakery.define(AccountWarning) do
  created_at { Time.current }
end

# Instance is a read-only database view. Never bake!/persist it as a parent of
# InstanceModerationNote; keeping it unset is enough for a valid in-memory bake.
FactoryBakery.define(InstanceModerationNote) do
  skip :instance
  domain { 'example.com' } # skip also suppresses the natural-key FK column
end

# AccountAlias#set_uri runs ResolveAccountService before validation. A remote
# acct (user@domain) makes it send a webfinger HTTP request; a bare local
# username returns the local account straight from the database. So alias
# another persisted local account: no network, and set_uri fills uri itself.
FactoryBakery.define(AccountAlias) do
  account { FactoryBakery.bake!(Account) }
  acct { FactoryBakery.bake!(Account).username }
end

# AccountMigration requires a target account whose also_known_as contains the
# source account's ActivityPub URI (account_migration.rb:83) and a live lookup
# (account_migration.rb:70). A persisted local source/target pair satisfies both.
FactoryBakery.define(AccountMigration) do
  source = nil
  target = nil
  account { source = FactoryBakery.bake!(Account) }
  target_account do
    target = FactoryBakery.bake!(Account, also_known_as: [ActivityPub::TagManager.instance.uri_for(source)])
  end
  # A local username lets ResolveAccountService (account_migration.rb:70) find
  # the target without any network call.
  acct { target.username }
end

# AccountPin validates an actual persisted Follow (account_pin.rb:26).
FactoryBakery.define(AccountPin) do
  pin_account = nil
  account { pin_account = FactoryBakery.bake!(Account) }
  target_account do
    target = FactoryBakery.bake!(Account)
    FactoryBakery.bake!(Follow, account: pin_account, target_account: target)
    target
  end
end

# PollOptionsValidator needs >= 2 options and PollExpirationValidator needs an
# expiry within 5.minutes..1.month (app/validators/poll_expiration_validator.rb).
FactoryBakery.define(Poll) do
  options { ['smoke option one', 'smoke option two'] }
  expires_at { 1.day.from_now }
end

# PollVote checks the chosen option and forbids voting on your own poll.
FactoryBakery.define(PollVote) do
  # persist: the own-poll check compares poll.account_id with account_id, which
  # are both nil while the records are unsaved. strategy: :fresh, because
  # reusing an account could pick the poll's own author.
  association :poll, persist: true
  association :account, persist: true, strategy: :fresh
  choice { 0 }
end

# SiteUpload's Paperclip styles lambda indexes STYLES by var (site_upload.rb:60);
# an unknown generated var yields nil and Paperclip raises each_pair on nil.
FactoryBakery.define(SiteUpload) do
  var { 'mascot' }
end

# TermsOfService requires changelog + a future, unique effective_date once
# published (terms_of_service.rb:23,72-77).
FactoryBakery.define(TermsOfService) do
  published_at { nil }
  changelog { 'smoke changelog' }
  effective_date { Date.current + SecureRandom.random_number(1..300) }
end

# WebPushKeyValidator runs a real encryption with the EC key and auth secret.
_push_curve = OpenSSL::PKey::EC.generate('prime256v1')
_push_p256dh = Base64.urlsafe_encode64(_push_curve.public_key.to_bn.to_s(2))
_push_auth = Base64.urlsafe_encode64(Random.new.bytes(16))
FactoryBakery.define(Web::PushSubscription) do
  key_p256dh { _push_p256dh }
  key_auth { _push_auth }
end

# Webhook#events must come from the fixed EVENTS list (webhook.rb:18-26,80).
FactoryBakery.define(Webhook) do
  events { ['status.created'] }
end

# Follow/FollowRequest validate :languages with the app's language validator;
# :all mode otherwise fills it with words that are not valid locale codes.
FactoryBakery.define(Follow) do
  languages { [] }
end
FactoryBakery.define(FollowRequest) do
  languages { [] }
end

# Remaining :all-mode cycle breakers belong on the collection side so that a
# standalone child still auto-builds its own required parent.
FactoryBakery.define(Collection) do
  # user_does_not_exceed_limit reads account.user.role.collection_limit
  # (collection.rb:118-122). A local account backed by a user with no role
  # resolves to UserRole.everyone, so the limit is always satisfiable.
  local { true }
  account { FactoryBakery.bake!(User, role: nil).account }
  skip :collection_items
end
FactoryBakery.define(List) do
  skip :list_accounts
end
FactoryBakery.define(ListAccount) do
  list { FactoryBakery.bake!(List, account: FactoryBakery.bake!(Account)) }
  association :account do |membership|
    followed = FactoryBakery.bake!(Account)
    FactoryBakery.bake!(Follow, account: membership.list.account, target_account: followed)
    followed
  end
  skip :follow, :follow_request
end

# Both association readers use account_id. Populate the summary table, which
# Mastodon normally maintains through AccountSummary.refresh.
FactoryBakery.define(FollowRecommendation) do
  account_id do
    account = FactoryBakery.bake!(Account)
    AccountSummary.insert_all!([{ account_id: account.id }])
    account.id
  end
end

FactoryBakery.define(Status) do
  text { 'smoke status text' }
  skip :bookmarks, :quotes, :reblogs, :replies, :media_attachments
end
FactoryBakery.define(Quote) do
  skip :quoted_status
end
FactoryBakery.define(Conversation) do
  skip :statuses
end
FactoryBakery.define(FeaturedTag) do
  # set_tag resolves the tag by name. Giving it an unsaved Tag instead makes
  # the callback save the Tag and any optional descendants while validating.
  skip :tag
  name { "smoke#{SecureRandom.hex(5)}" }
end
FactoryBakery.define(AccountConversation) do
  # set_last_status derives the association from persisted status IDs.
  skip :last_status
  status_ids do
    FactoryBakery::Associations.with(mode: :required_only) { [FactoryBakery.bake!(Status).id] }
  end
end
# validate_status_access (custom_filter_status.rb) runs StatusPolicy#show? for the
# filter's account. One persisted account owns both the filter and a public
# status, so the status is visible to the account that applies the filter.
FactoryBakery.define(CustomFilterStatus) do
  association(:custom_filter) do |_custom_filter_status|
    FactoryBakery.bake!(CustomFilter, account: FactoryBakery.bake!(Account))
  end
  association(:status) do |custom_filter_status|
    FactoryBakery.bake!(Status, account: custom_filter_status.custom_filter.account, reblog: nil, visibility: :public)
  end
end

FactoryBakery.define(StatusPin) do
  pin_account = nil
  account { pin_account = FactoryBakery.bake!(Account) }
  status { FactoryBakery.bake!(Status, account: pin_account, reblog: nil, visibility: :public) }
end
