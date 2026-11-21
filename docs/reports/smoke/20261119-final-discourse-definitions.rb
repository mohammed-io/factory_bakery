# frozen_string_literal: true

# FactoryBakery custom factories for the real-world full-boot smoke run.
# Real .rb file, require-loaded by the rails runner (SMOKE_DEFINITIONS).
# TEST-ONLY definitions living in the disposable clone, never in the gem.

require 'securerandom'
require 'factory_bakery/attachments'

# Deterministic OpenAI provider setup shared by all LLM models.
# Bakes a fresh, valid LlmModel (open_ai, vision disabled) inside the current
# bake graph. Avoids flaky random providers (bedrock/vertex) that require
# region/project_id, and avoids vision / legacy-user validations.
def smoke_llm_model
  LlmModel.create!(
    provider: LlmModel::OPEN_AI_PROVIDER_NAME,
    name: "smoke_llm_#{SecureRandom.hex(4)}",
    display_name: 'Smoke LLM',
    tokenizer: 'DiscourseAi::Tokenizer::OpenAiTokenizer',
    url: 'https://example.com/v1/chat/completions',
    api_key: 'test-key',
    max_prompt_tokens: 4096,
    max_output_tokens: 1000,
    input_cost: 0,
    output_cost: 0,
    cached_input_cost: 0,
    provider_params: {},
    ai_secret_id: nil,
    user_id: nil,
    vision_llm_model_id: nil,
    vision_enabled: false,
  )
end

# Discourse sets belongs_to_required_by_default = false, so UserEmail#user is
# optional. Break the User -> primary_email -> UserEmail -> User cycle.
FactoryBakery.define(UserEmail) do
  user { nil }
end

FactoryBakery.define(User) do
  # Default username filler violates Discourse's alphanumeric/20-char validator.
  username { "fb_#{SecureRandom.hex(5)}" }
  password { 'SmokePass123!' }
  secure_identifier { SecureRandom.hex(12) }
  # has_one :primary_email -> UserEmail; validation requires a real address.
  primary_email do
    FactoryBakery.bake(UserEmail, email: "fb_#{SecureRandom.hex(5)}@example.com", primary: true)
  end
end

FactoryBakery.define(Category) do
  # Regex \A(\h{6}|\h{3})\z defeats the synthesizer (it emits "hhhhhh").
  color { 'FF0000' }
  text_color { '00FF00' }
  # emoji_exists validator requires a real Emoji row; nil skips it.
  emoji { nil }
end

FactoryBakery.define(AccessControlList) do
  target_id { nil }
  target_type { nil }
  association :target do |_owner|
    FactoryBakery.bake(Group)
  end
end

FactoryBakery.define(AiSummary) do
  target_id { nil }
  target_type { nil }
  association :target do |_owner|
    FactoryBakery.bake(Topic)
  end
end

FactoryBakery.define(AiAgent) do
  examples { [] }
end

FactoryBakery.define(AdPlugin::AdImpression) do
  # AdPlugin::AdType enum: house / adsense / dfp / amazon / carbon / adbutler.
  # Non-house ads must have a nil house-ad FK.
  ad_type { :adsense }
  ad_plugin_house_ad_id { nil }
end

FactoryBakery.define(AiMcpServer) do
  url { 'https://discourse.org' }
end

FactoryBakery.define(Assignment) do
  assigned_to_id { nil }
  assigned_to_type { nil }
  association :assigned_to do |_owner|
    FactoryBakery.bake(User)
  end
end

FactoryBakery.define(Blog::Path) do
  path { "/smoke-path-#{SecureRandom.hex(6)}" }
end

FactoryBakery.define(Blog::Publication) do
  path { "/smoke-pub-#{SecureRandom.hex(6)}" }
end

# --- smoke round 2 -------------------------------------------------------

# UserStatus#emoji_exists (app/models/user_status.rb:17-19) requires a real emoji.
FactoryBakery.define(UserStatus) do
  emoji { 'smile' }
  ends_at { nil }
end

# The blocks normalizer expects an array; duplicate detection needs a channel and author.
FactoryBakery.define(Chat::Message) do
  blocks { nil }
  message { "FactoryBakery chat message #{SecureRandom.hex(6)}" }
  user { Discourse.system_user }
  last_editor { Discourse.system_user }
  chat_channel { FactoryBakery.bake!(Chat::Channel) }
  in_reply_to { nil }
  thread { nil }
end

FactoryBakery.define(CompletionPrompt) do
  messages { [] }
end

# The chat_message reflection names a missing ChatMessage class; use the FK directly.
FactoryBakery.define(Chat::MessageSearchData) do
  chat_message_id { FactoryBakery.bake!(Chat::Message).id }
  search_data { "'smoke':1" }
end

# Group name trust level / format rules (app/models/group.rb).
FactoryBakery.define(Group) do
  name { "smoke_group_#{SecureRandom.hex(4)}" }
  trust_level { 0 }
end

# WebHook event types (app/models/web_hook.rb:19).
FactoryBakery.define(WebHook) do
  payload_url { 'https://example.com/webhook' }
  content_type { 'application/json' }
  last_delivery_status { 'inactive' }
  wildcard_web_hook { true } # satisfies web_hook.rb:19 without seeded event types
end

FactoryBakery.define(WatchedWordGroup) do
  action { 1 }
  # watched_words_validation errors when the group has no watched word rows.
  association :watched_words do |_owner|
    [FactoryBakery.bake!(WatchedWord, watched_word_group_id: nil)]
  end
end

FactoryBakery.define(FormTemplate) do
  # FormTemplateYamlValidator (lib/validators/form_template_yaml_validator.rb)
  # wants an Array of hashes, each with a unique non-reserved `id` and a type
  # from ALLOWED_TYPES.
  template do
    [{ "id" => "fb_field", "type" => "input", "label" => "Smoke" }].to_yaml
  end
end

# DiscourseMcp.registry is filled by CorePrimitives.register! in
# config/initializers/020-discourse-mcp.rb; McpGroupScope#scope_is_registered
# only accepts one of the registered required scopes.
FactoryBakery.define(McpGroupScope) do
  scope { DiscourseMcp.registry.scopes.first }
end

# McpOauthClient#redirect_uris_are_absolute: https anywhere, http only on
# localhost/loopback.
FactoryBakery.define(McpOauthClient) do
  redirect_uris { ["https://example.com/oauth/callback"] }
end

# DiscourseChatIntegration::Provider.provider_names comes from the provider
# classes the plugin registers; "discord" is always among them.
FactoryBakery.define(DiscourseChatIntegration::Channel) do
  key { nil } # PluginModel assigns the channel prefix before saving.
  type_name { 'JSON' }
  plugin_name { DiscourseChatIntegration::PluginModel::PLUGIN_NAME }
  provider { 'discord' }
  # Channel#data_valid? requires data keys to match the provider's
  # CHANNEL_PARAMETERS exactly (discord: name + webhook_url).
  data { { 'name' => "fb_#{SecureRandom.hex(4)}", 'webhook_url' => "https://discord.com/api/webhooks/#{SecureRandom.hex(8)}" } }
end

# channel_valid? requires a stored channel ID inside the rule's JSON value.
FactoryBakery.define(DiscourseChatIntegration::Rule) do
  key { nil }
  type_name { 'JSON' }
  plugin_name { DiscourseChatIntegration::PluginModel::PLUGIN_NAME }
  channel_id { FactoryBakery.bake!(DiscourseChatIntegration::Channel).id }
  type { 'normal' }
  filter { 'watch' }
  # "normal" rules may not set category_id/group_id (category_valid?/
  # group_valid?). Assigning nil keeps both out of the value hash.
  category_id { nil }
  group_id { nil }
  tags { nil }
end

FactoryBakery.define(AdminDashboardReport) do
  # multi_row_cards_must_be_full_width: a multi-row card must span both columns.
  rows { 1 }
  cols { 1 }
  # source_must_be_registered resolves the provider at save time, once the
  # app's admin dashboard registry has its providers.
  source { 'core_report' }
end

FactoryBakery.define(UserNotificationSchedule) do
  # has_valid_times: start must be <= end and within 0..1410 / 0..1440.
  day_0_start_time { 480 }
  day_0_end_time { 1020 }
  day_1_start_time { 480 }
  day_1_end_time { 1020 }
  day_2_start_time { 480 }
  day_2_end_time { 1020 }
  day_3_start_time { 480 }
  day_3_end_time { 1020 }
  day_4_start_time { 480 }
  day_4_end_time { 1020 }
  day_5_start_time { 480 }
  day_5_end_time { 1020 }
  day_6_start_time { 480 }
  day_6_end_time { 1020 }
end

FactoryBakery.define(SiteSettingLocalization) do
  # setting_is_localizable: the name must be a localizable site setting
  # (config/site_settings.yml). "title" is localizable and not cooked.
  setting_name { 'title' }
  cooked { nil }
end

# --- smoke round 6 -------------------------------------------------------

FactoryBakery.define(AiModerationSetting) do
  # Postgres enum ai_moderation_setting_type (plugins/discourse-ai/db/migrate/
  # 20241206030229_add_ai_moderation_settings.rb).
  setting_type { 'spam' }
  # model_present: one of llm_model / decision_model must be set.
  association :decision_model do |_owner|
    FactoryBakery.bake!(DecisionModel)
  end
end

# Reviewable#type is the STI discriminator; ReviewableNote#reviewable_id is a
# plain column with no belongs_to the mapper can fill.
FactoryBakery.define(Reviewable) do
  type { 'ReviewableQueuedPost' }
  created_by { Discourse.system_user }
  target_created_by { nil }
  topic { nil }
  category { nil }
  target { nil }
end

FactoryBakery.define(ReviewableNote) do
  reviewable_id { FactoryBakery.bake!(Reviewable).id }
end

# ensure_supported_linkable_type and presence require a supported link target.
FactoryBakery.define(SidebarSectionLink) do
  linkable { Category.find(SiteSetting.uncategorized_category_id) }
  user { FactoryBakery.bake!(User) }
  sidebar_section { nil }
end

# link_to_self compares topic IDs; an external link uses only a source topic.
FactoryBakery.define(TopicLink) do
  url { "https://example.com/#{SecureRandom.hex(8)}" }
  domain { 'example.com' }
  topic { FactoryBakery.bake!(Topic, user: Discourse.system_user) }
  user { Discourse.system_user }
  post { nil }
  link_topic { nil }
  link_post { nil }
end

FactoryBakery.define(TopicLinkClick) do
  topic_link { FactoryBakery.bake!(TopicLink) }
  user { Discourse.system_user }
end

# The comparison validator requires distinct invitee and inviter IDs.
FactoryBakery.define(Live::Invite) do
  user { FactoryBakery.bake!(User) }
  invited_by { Discourse.system_user }
end

# generate_auto_slug runs before validation and is implemented by the STI subclass.
FactoryBakery.define(Chat::Channel) do
  initialize_with(type: 'CategoryChannel')
  type { 'CategoryChannel' }
  name { "FactoryBakery channel #{SecureRandom.hex(6)}" }
  chatable { Category.find(SiteSetting.uncategorized_category_id) }
  last_message { nil }
end

# alias_declared and secret_exists require persisted records with a matching contract.
FactoryBakery.define(AiToolSecretBinding) do
  public_send(:alias) { 'smoke_token' }
  ai_tool do
    name = "smoke_tool_#{SecureRandom.hex(6)}"
    AiTool.create!(name: name, tool_name: name, description: 'Smoke tool', summary: 'Smoke tool',
                   script: 'function invoke() { return {}; }', created_by: Discourse.system_user,
                   secret_contracts: [{ 'alias' => 'smoke_token' }])
  end
  ai_secret { AiSecret.create!(name: "smoke_secret_#{SecureRandom.hex(6)}", secret: 'test-value') }
  created_by { Discourse.system_user }
end

# metadata_schema checks the component against the selected script's fields.
FactoryBakery.define(DiscourseAutomation::Field) do
  automation do
    DiscourseAutomation::Automation.create!(name: 'Smoke automation', script: 'auto_responder',
                                            trigger: 'post_created_edited', enabled: false,
                                            last_updated_by: Discourse.system_user)
  end
  target { 'script' }
  name { 'once' }
  component { 'boolean' }
  metadata { { 'value' => true } }
end

# check_interpolation_keys looks up the original English translation.
FactoryBakery.define(TranslationOverride) do
  locale { 'en' }
  translation_key { 'email_from' }
  value { '%{user_name}' }
end

# required_provider_params and valid_vision_configuration run when the quota's model saves.
FactoryBakery.define(LlmQuotaUsage) do
  user { Discourse.system_user }
  llm_quota do
    llm = LlmModel.create!(provider: 'open_ai', name: 'gpt-4o-mini', display_name: 'Smoke LLM',
                           tokenizer: 'DiscourseAi::Tokenizer::OpenAiTokenizer',
                           url: 'https://example.com/v1/chat/completions',
                           api_key: 'test-key', max_prompt_tokens: 4096)
    LlmQuota.create!(llm_model: llm, group: Group.find(Group::AUTO_GROUPS[:everyone]),
                     duration_seconds: 3600, max_tokens: 1000)
  end
end

# Deterministic open_ai LlmModel shared by all LLM credit models. Forces the
# provider so random bedrock/vertex providers (which need region/project_id)
# are never picked. Disables vision and legacy user association so "all" mode
# (passes C/D) stays valid.
FactoryBakery.define(LlmModel) do
  provider { LlmModel::OPEN_AI_PROVIDER_NAME }
  name { "smoke_llm_#{SecureRandom.hex(4)}" }
  display_name { 'Smoke LLM' }
  tokenizer { 'DiscourseAi::Tokenizer::OpenAiTokenizer' }
  url { 'https://example.com/v1/chat/completions' }
  api_key { 'test-key' }
  max_prompt_tokens { 4096 }
  max_output_tokens { 1000 }
  input_cost { 0 }
  output_cost { 0 }
  cached_input_cost { 0 }
  provider_params { {} }
  ai_secret_id { nil }
  user_id { nil }
  vision_llm_model_id { nil }
  vision_enabled { false }
end

# LlmQuota belongs_to llm_model + group; needs at least one limit (max_tokens).
FactoryBakery.define(LlmQuota) do
  llm_model { smoke_llm_model }
  group { Group.find(Group::AUTO_GROUPS[:everyone]) }
  duration_seconds { 3600 }
  max_tokens { 1000 }
end

# LlmCreditAllocation: llm_model unique, daily_credits > 0, soft_limit 0..100.
FactoryBakery.define(LlmCreditAllocation) do
  llm_model { smoke_llm_model }
  daily_credits { 1000 }
  soft_limit_percentage { 80 }
end

# LlmCreditDailyUsage: llm_model + usage_date + credits_used >= 0.
FactoryBakery.define(LlmCreditDailyUsage) do
  llm_model { smoke_llm_model }
  usage_date { Date.current }
  credits_used { 0 }
end

# LlmFeatureCreditCost: llm_model + feature_name unique per model, credits_per_token >= 0.
FactoryBakery.define(LlmFeatureCreditCost) do
  llm_model { smoke_llm_model }
  feature_name { "smoke_feature_#{SecureRandom.hex(4)}" }
  credits_per_token { 1 }
end

# EmbeddingDefinition: forces open_ai provider (avoids bedrock region/model_id
# requirements) and a valid tokenizer. URL is required for non-bedrock providers.
FactoryBakery.define(EmbeddingDefinition) do
  provider { EmbeddingDefinition::OPEN_AI }
  display_name { "smoke_embedding_#{SecureRandom.hex(4)}" }
  tokenizer_class { 'DiscourseAi::Tokenizer::OpenAiTokenizer' }
  dimensions { 1536 }
  max_sequence_length { 512 }
  url { 'https://api.openai.com/v1/embeddings' }
  pg_function { '<=>' }
  api_key { 'test-key' }
end

# SkippedEmailLog: pick a valid non-custom reason_type so custom_reason is not
# required (and must be absent).
FactoryBakery.define(SkippedEmailLog) do
  email_type { 'user_email' }
  to_address { "smoke_#{SecureRandom.hex(4)}@example.com" }
  reason_type { SkippedEmailLog.reason_types[:exceeded_emails_limit] }
  custom_reason { nil }
end

# A minimal valid theme: name + user, not a component. theme_fields are not
# declared here; in "all" mode the heuristic auto-builds optional theme_field
# children and any that are invalid are discarded before the theme saves, so
# Theme#validate_theme_fields always passes.
FactoryBakery.define(Theme) do
  name { "smoke_theme_#{SecureRandom.hex(4)}" }
  user { Discourse.system_user }
  component { false }
  # Under :all these relations get auto-built with a random parent/child
  # theme that fails ThemeValidator ("Parent theme relation is invalid").
  skip :parent_theme_relation, :child_theme_relation
end

# ThemeSettingsMigration: needs a valid theme + theme_field (belongs_to, not
# optional) and unique (theme_id, version) / unique theme_field_id. The theme is
# baked with FactoryBakery (see the Theme definition); the theme_field is baked
# separately so the migration's theme_id/theme_field_id are independent.
FactoryBakery.define(ThemeSettingsMigration) do
  theme { FactoryBakery.bake!(Theme) }
  theme_field do
    FactoryBakery.bake!(
      ThemeField,
      name: "smoke_field_#{SecureRandom.hex(4)}",
      value: 'hello',
      target_id: Theme.targets[:common],
      type_id: ThemeField.types[:html],
    )
  end
  version { 1 }
  name { 'Smoke migration' }
  diff { { additions: [], deletions: [] }.to_json }
end

# ThemeTranslationOverride: pin a valid translation_key/locale/value and a real
# theme so check_interpolation_keys + capture_original_translation don't hit
# invalid YAML in "all" mode (passes C/D).
FactoryBakery.define(ThemeTranslationOverride) do
  locale { 'en' }
  translation_key { 'email_from' }
  value { '%{user_name}' }
  theme do
    t = Theme.new(name: "smoke_theme_#{SecureRandom.hex(4)}", user: Discourse.system_user, component: false)
    t.save!
    t
  end
end

# Permalink: exactly one of topic_id/post_id/category_id/tag_id/user_id/
# external_url must be set. Use external_url and nil the rest (pass D failure).
FactoryBakery.define(Permalink) do
  url { "https://example.com/smoke-#{SecureRandom.hex(8)}" }
  external_url { "/t/smoke-topic-#{SecureRandom.hex(4)}" }
  topic_id { nil }
  post_id { nil }
  category_id { nil }
  tag_id { nil }
  user_id { nil }
end

# EmbeddableHostTag: unique (embeddable_host_id, tag_id). Fresh embeddable_host
# + tag per bake avoids cross-bake category_tag_stats collisions (pass C) and
# tag synonyms errors (pass D). topic_tags is empty so no CategoryTagStat rows
# are created via TopicTag callbacks; target_tag_id is nil so the
# target_tag_validator (synonyms) never fires.
FactoryBakery.define(EmbeddableHostTag) do
  embeddable_host { FactoryBakery.bake!(EmbeddableHost) }
  tag { FactoryBakery.bake!(Tag, name: "smoke_tag_#{SecureRandom.hex(4)}", topic_tags: [], target_tag_id: nil) }
end

# ensure_can_comment requires an enabled Post Voting topic and a top-level post.
# post_voting_enabled must stay ON while the comment is validated:
# Topic#is_post_voting? (read by ensure_can_comment) checks the setting live, and
# Topic#ensure_regular_topic needs it while the question_answer topic bakes.
# Restoring it in an `ensure` here would run *before* the comment's valid? and
# break validation ("post_voting_not_enabled"). bake() does not persist the root
# record, so there is no after-persist hook to restore in; the setting stays
# enabled for the rest of the run. That is harmless: every other validation keyed
# on post_voting_enabled (Topic#ensure_regular_topic, Post#ensure_only_replies)
# additionally requires a question_answer subtype topic, which no other smoke
# model creates.
FactoryBakery.define(PostVotingComment) do
  post do
    SiteSetting.post_voting_enabled = true
    user = FactoryBakery.bake!(User)
    topic = FactoryBakery.bake!(Topic, subtype: Topic::POST_VOTING_SUBTYPE, user: user)
    FactoryBakery.bake!(Post, topic: topic, user: user)
  end
  user { Discourse.system_user }
  raw { 'This comment explains why the proposed answer works.' }
end

# ensure_valid_vote rejects self-votes; ensure_valid_comment allows only upvotes.
FactoryBakery.define(PostVotingVote) do
  votable { FactoryBakery.bake!(PostVotingComment, user: FactoryBakery.bake!(User)) }
  user { Discourse.system_user }
  direction { 'up' }
end

# valid_bookmarkable_type accepts a registered target; a reminder is optional.
FactoryBakery.define(Bookmark) do
  bookmarkable { FactoryBakery.bake!(Topic) }
  user { Discourse.system_user }
  name { 'Smoke bookmark' }
  reminder_at { nil }
end

# ensure_same_topic requires both posts to share the same persisted topic.
FactoryBakery.define(PostReply) do
  association(:post) { FactoryBakery.bake!(Post) }
  association(:reply) do |post_reply|
    FactoryBakery.bake!(Post, topic: post_reply.post.topic, reply_to_post_number: post_reply.post.post_number)
  end
end

# The sharing API requires a Topic and the model validates nonempty context.
# State is scoped to one bake (fresh post each time) so rolled-back post IDs
# are never reused across passes.
FactoryBakery.define(SharedAiConversation) do
  target { FactoryBakery.bake!(Post).topic }
  user { Discourse.system_user }
  context do
    post = FactoryBakery.bake!(Post)
    [{ 'id' => post.id, 'user_id' => post.user_id, 'created_at' => post.created_at.iso8601, 'cooked' => post.cooked }]
  end
end
