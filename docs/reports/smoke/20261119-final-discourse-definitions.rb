# frozen_string_literal: true

# FactoryBakery custom factories for the real-world full-boot smoke run.
# Real .rb file, require-loaded by the rails runner (SMOKE_DEFINITIONS).
# TEST-ONLY definitions living in the disposable clone, never in the gem.

require 'securerandom'
require 'factory_bakery/attachments'

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

# JsonFiller emits a Hash; these app validators iterate the JSON value as an
# Array of hashes (chat/message.rb:127-133, completion_prompt.rb:61-66).
FactoryBakery.define(Chat::Message) do
  blocks { [] }
end
FactoryBakery.define(Chat::NullMessage) do
  blocks { [] }
end
FactoryBakery.define(CompletionPrompt) do
  messages { [] }
end

# The app maps the legacy "ChatMessage" polymorphic name to Chat::Message
# (plugins/chat/app/models/chat/message.rb:137); the gem's discovery does not.
FactoryBakery.define(Chat::MessageSearchData) do
  association :chat_message, factory: Chat::Message
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
  watched_words { [] }
end

FactoryBakery.define(FormTemplate) do
  template { "---\n{}\n" }
end

