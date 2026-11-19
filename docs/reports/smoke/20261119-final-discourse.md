# Final real-world smoke report — Discourse (2026-11-19)

Full-boot smoke of the frozen gem snapshot `af756ed` against the real Discourse
clone (`58f5edd`, Rails 8.1.4.1, PostgreSQL `fb_probe_pg:55432`, Redis
`fb-smoke-redis:56379`, all 402 tables loaded from the app's real
`db/structure.sql`). 414 eligible AR models, four passes per round:

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
active in **both** rounds (`require 'factory_bakery/attachments'`). Outbound
network stays off; the gem never opens a socket.

---

## 1. Summary

### Automatic round — no app definitions (only `require 'factory_bakery/attachments'`)

| Pass | Mode / strategy | Models | Valid | Invalid | Error | Timeout | Pass rate |
|---|---|---:|---:|---:|---:|---:|---:|
| A | required_only / fresh | 414 | 327 | 21 | 66 | 0 | **79.0 %** |
| B | required_only / reuse | 414 | 376 | 25 | 13 | 0 | 90.8 % |
| C | all / fresh | 414 | 81 | 7 | 326 | 0 | 19.6 % |
| D | all / reuse | 414 | 308 | 60 | 46 | 0 | 74.4 % |

### Definitions round — `smoke_definitions.rb` (+ attachments plugin)

| Pass | Mode / strategy | Models | Valid | Invalid | Error | Timeout | Pass rate |
|---|---|---:|---:|---:|---:|---:|---:|
| A | required_only / fresh | 414 | **366** | 19 | 29 | 0 | **88.4 %** |
| B | required_only / reuse | 414 | **383** | 19 | 12 | 0 | **92.5 %** |
| C | all / fresh | 414 | 129 | 13 | 272 | 0 | 31.2 % |
| D | all / reuse | 414 | 313 | 55 | 46 | 0 | 75.6 % |

### Goals and previous runs

| Metric | Result |
|---|---|
| Overall automatic pass A vs **80 % goal** | **79.0 % — 1.0 pt short** (327/414; 332 would meet it) |
| Automatic pass A vs previous run (`all-models-baseline.jsonl`) | 207/414 (50.0 %) → 327/414 (**+29.0 pts**) |
| Defined pass A vs previous run (`all-models-defined.jsonl`) | 288/414 (69.6 %) → 366/414 (**+18.8 pts**) |
| Best defined result | A 88.4 %, B 92.5 %; C/D remain limited by gem `:all`-mode defects (§5) |

Raw JSONL:
`/Users/mohammed/Projects/factory_bakery/.smoke-tests/real-app-cache/discourse/final-auto.jsonl`
and `.../final-defined.jsonl`.

---

## 2. Works automatically

Every one of these 327 models bakes valid in pass A with **no definition at
all** (only the attachments plugin require). Trailing letters are the passes
in which the same zero-definition bake is valid.

```ruby
FactoryBakery.bake(AccessControlList)  # valid in ABD
FactoryBakery.bake(AdPlugin::HouseAd)  # valid in ABCD
FactoryBakery.bake(AdPlugin::HouseAdRoute)  # valid in ABCD
FactoryBakery.bake(AdminDashboardSection)  # valid in ABCD
FactoryBakery.bake(AdminNotice)  # valid in ABCD
FactoryBakery.bake(AiAgent)  # valid in AB
FactoryBakery.bake(AiApiAuditLog)  # valid in ABD
FactoryBakery.bake(AiApiRequestStat)  # valid in ABCD
FactoryBakery.bake(AiMcpOauthToken)  # valid in ABD
FactoryBakery.bake(AiMcpServer)  # valid in AB
FactoryBakery.bake(AiReviewableSuggestion)  # valid in ABD
FactoryBakery.bake(AiSecret)  # valid in AB
FactoryBakery.bake(AiSummary)  # valid in ABD
FactoryBakery.bake(AiTool)  # valid in AB
FactoryBakery.bake(AiToolAction)  # valid in ABD
FactoryBakery.bake(AllowedPmUser)  # valid in ABD
FactoryBakery.bake(AnonymousUser)  # valid in ABD
FactoryBakery.bake(ApiKey)  # valid in ABD
FactoryBakery.bake(ApiKeyScope)  # valid in ABCD
FactoryBakery.bake(AppearanceChange)  # valid in ABD
FactoryBakery.bake(ApplicationRequest)  # valid in ABCD
FactoryBakery.bake(AskAiLog)  # valid in ABD
FactoryBakery.bake(AskAiReport)  # valid in ABD
FactoryBakery.bake(AskAiReportSubject)  # valid in ABD
FactoryBakery.bake(AskAiReportSubjectAsk)  # valid in ABCD
FactoryBakery.bake(Assignment)  # valid in ABD
FactoryBakery.bake(AssociatedGroup)  # valid in ABCD
FactoryBakery.bake(BackupDraftTopic)  # valid in ABD
FactoryBakery.bake(BackupMetadata)  # valid in ABCD
FactoryBakery.bake(Badge)  # valid in AB
FactoryBakery.bake(BadgeGrouping)  # valid in AB
FactoryBakery.bake(BadgeType)  # valid in ABD
FactoryBakery.bake(BaseTimer)  # valid in ABD
FactoryBakery.bake(Blog::Review)  # valid in ABD
FactoryBakery.bake(Blog::ReviewFeedback)  # valid in ABD
FactoryBakery.bake(Boards::Board)  # valid in AB
FactoryBakery.bake(Boards::Column)  # valid in AB
FactoryBakery.bake(BrowserPageviewCountryDailyRollup)  # valid in ABCD
FactoryBakery.bake(BrowserPageviewCrawlerDailyRollup)  # valid in ABCD
FactoryBakery.bake(BrowserPageviewEntryUrlDailyRollup)  # valid in ABCD
FactoryBakery.bake(BrowserPageviewEvent)  # valid in ABCD
FactoryBakery.bake(BrowserPageviewEventScore)  # valid in ABCD
FactoryBakery.bake(BrowserPageviewReferrerDailyRollup)  # valid in ABCD
FactoryBakery.bake(BrowserPageviewSessionEngagement)  # valid in ABCD
FactoryBakery.bake(BrowserPageviewSessionEngagementDailyRollup)  # valid in ABCD
FactoryBakery.bake(Category)  # valid in AB
FactoryBakery.bake(CategoryActivityDailyRollup)  # valid in ABD
FactoryBakery.bake(CategoryCustomField)  # valid in ABD
FactoryBakery.bake(CategoryFeaturedTopic)  # valid in ABD
FactoryBakery.bake(CategoryFormTemplate)  # valid in ABD
FactoryBakery.bake(CategoryGroup)  # valid in ABD
FactoryBakery.bake(CategoryLocalization)  # valid in ABD
FactoryBakery.bake(CategoryModerationGroup)  # valid in ABD
FactoryBakery.bake(CategoryPostingReviewGroup)  # valid in ABD
FactoryBakery.bake(CategoryRequiredTagGroup)  # valid in ABD
FactoryBakery.bake(CategorySearchData)  # valid in ABD
FactoryBakery.bake(CategorySetting)  # valid in ABD
FactoryBakery.bake(CategoryTag)  # valid in ABD
FactoryBakery.bake(CategoryTagGroup)  # valid in ABD
FactoryBakery.bake(CategoryTagStat)  # valid in ABD
FactoryBakery.bake(CategoryUser)  # valid in ABD
FactoryBakery.bake(Chat::AllMention)  # valid in AB
FactoryBakery.bake(Chat::CategoryChannel)  # valid in AB
FactoryBakery.bake(Chat::ChannelArchive)  # valid in ABD
FactoryBakery.bake(Chat::ChannelCustomField)  # valid in ABD
FactoryBakery.bake(Chat::DirectMessage)  # valid in ABD
FactoryBakery.bake(Chat::DirectMessageChannel)  # valid in AB
FactoryBakery.bake(Chat::DirectMessageUser)  # valid in ABD
FactoryBakery.bake(Chat::DiscoverableBot)  # valid in ABD
FactoryBakery.bake(Chat::Draft)  # valid in ABD
FactoryBakery.bake(Chat::GroupMention)  # valid in AB
FactoryBakery.bake(Chat::HereMention)  # valid in AB
FactoryBakery.bake(Chat::IncomingWebhook)  # valid in ABD
FactoryBakery.bake(Chat::Mention)  # valid in AB
FactoryBakery.bake(Chat::MentionNotification)  # valid in ABD
FactoryBakery.bake(Chat::MessageCustomField)  # valid in AB
FactoryBakery.bake(Chat::MessageHotlinkedMedia)  # valid in AB
FactoryBakery.bake(Chat::MessageInteraction)  # valid in AB
FactoryBakery.bake(Chat::MessageLink)  # valid in AB
FactoryBakery.bake(Chat::MessageReaction)  # valid in AB
FactoryBakery.bake(Chat::MessageRevision)  # valid in AB
FactoryBakery.bake(Chat::NullUser)  # valid in AB
FactoryBakery.bake(Chat::PinnedMessage)  # valid in AB
FactoryBakery.bake(Chat::ReviewableMessage)  # valid in AB
FactoryBakery.bake(Chat::Thread)  # valid in AB
FactoryBakery.bake(Chat::ThreadCustomField)  # valid in ABCD
FactoryBakery.bake(Chat::UserChatChannelMembership)  # valid in AB
FactoryBakery.bake(Chat::UserChatThreadMembership)  # valid in AB
FactoryBakery.bake(Chat::UserMention)  # valid in AB
FactoryBakery.bake(Chat::WebhookEvent)  # valid in AB
FactoryBakery.bake(ChatMessageCustomPrompt)  # valid in ABCD
FactoryBakery.bake(ChildTheme)  # valid in AB
FactoryBakery.bake(ClassificationResult)  # valid in ABCD
FactoryBakery.bake(ColorScheme)  # valid in ABD
FactoryBakery.bake(ColorSchemeColor)  # valid in ABCD
FactoryBakery.bake(CustomEmoji)  # valid in ABD
FactoryBakery.bake(DecisionModel)  # valid in AB
FactoryBakery.bake(DecisionModelCreditAllocation)  # valid in ABD
FactoryBakery.bake(DecisionModelCreditDailyUsage)  # valid in ABD
FactoryBakery.bake(DecisionModelFeatureCreditCost)  # valid in ABD
FactoryBakery.bake(Developer)  # valid in ABD
FactoryBakery.bake(DirectoryColumn)  # valid in ABCD
FactoryBakery.bake(DirectoryItem)  # valid in AB
FactoryBakery.bake(DiscourseAi::AiBot::ConversationStar)  # valid in ABD
FactoryBakery.bake(DiscourseAutomation::Automation)  # valid in AB
FactoryBakery.bake(DiscourseAutomation::PendingAutomation)  # valid in ABCD
FactoryBakery.bake(DiscourseAutomation::PendingPm)  # valid in ABCD
FactoryBakery.bake(DiscourseAutomation::Stat)  # valid in ABCD
FactoryBakery.bake(DiscourseAutomation::UserGlobalNotice)  # valid in ABD
FactoryBakery.bake(DiscourseChatIntegration::PluginModel)  # valid in ABCD
FactoryBakery.bake(DiscourseDataExplorer::Query)  # valid in AB
FactoryBakery.bake(DiscourseDataExplorer::QueryGroup)  # valid in AB
FactoryBakery.bake(DiscourseDataExplorer::QueryStat)  # valid in ABCD
FactoryBakery.bake(DiscourseDataExplorer::QueryTag)  # valid in ABCD
FactoryBakery.bake(DiscourseDataExplorer::QueryTagMapping)  # valid in ABCD
FactoryBakery.bake(DiscourseEvents::Calendar::Event)  # valid in ABD
FactoryBakery.bake(DiscourseEvents::Events::EventDate)  # valid in ABD
FactoryBakery.bake(DiscourseEvents::Holidays::DisabledHoliday)  # valid in ABCD
FactoryBakery.bake(DiscourseEvents::Livestream::TopicChatChannel)  # valid in ABD
FactoryBakery.bake(DiscourseGamification::GamificationLeaderboard)  # valid in ABD
FactoryBakery.bake(DiscourseGamification::GamificationLeaderboardScore)  # valid in ABD
FactoryBakery.bake(DiscourseGamification::GamificationScoreEvent)  # valid in ABD
FactoryBakery.bake(DiscourseGithubPlugin::GithubCommit)  # valid in ABCD
FactoryBakery.bake(DiscourseGithubPlugin::GithubRepo)  # valid in ABCD
FactoryBakery.bake(DiscourseReactions::Reaction)  # valid in ABD
FactoryBakery.bake(DiscourseReactions::ReactionUser)  # valid in ABD
FactoryBakery.bake(DiscourseRssPolling::PollAttempt)  # valid in ABCD
FactoryBakery.bake(DiscourseRssPolling::RssFeed)  # valid in ABD
FactoryBakery.bake(DiscourseSubscriptions::Customer)  # valid in ABCD
FactoryBakery.bake(DiscourseSubscriptions::Product)  # valid in ABCD
FactoryBakery.bake(DiscourseSubscriptions::Subscription)  # valid in ABCD
FactoryBakery.bake(DiscourseTopicVoting::CategorySetting)  # valid in ABD
FactoryBakery.bake(DiscourseTopicVoting::TopicVoteCount)  # valid in ABD
FactoryBakery.bake(DiscourseTopicVoting::Vote)  # valid in ABD
FactoryBakery.bake(DiscourseWorkflows::AiAuthoringSession)  # valid in ABD
FactoryBakery.bake(DiscourseWorkflows::Credential)  # valid in ABCD
FactoryBakery.bake(DiscourseWorkflows::DataTable)  # valid in ABCD
FactoryBakery.bake(DiscourseWorkflows::Execution)  # valid in ABD
FactoryBakery.bake(DiscourseWorkflows::ExecutionData)  # valid in ABCD
FactoryBakery.bake(DiscourseWorkflows::ExecutionStat)  # valid in ABCD
FactoryBakery.bake(DiscourseWorkflows::ReviewableAgent)  # valid in ABD
FactoryBakery.bake(DiscourseWorkflows::Variable)  # valid in ABD
FactoryBakery.bake(DiscourseWorkflows::Webhook)  # valid in ABD
FactoryBakery.bake(DiscourseWorkflows::Workflow)  # valid in AB
FactoryBakery.bake(DiscourseWorkflows::WorkflowCallRun)  # valid in ABD
FactoryBakery.bake(DiscourseWorkflows::WorkflowDependency)  # valid in ABD
FactoryBakery.bake(DiscourseWorkflows::WorkflowPublishHistory)  # valid in ABD
FactoryBakery.bake(DiscourseWorkflows::WorkflowTag)  # valid in ABCD
FactoryBakery.bake(DiscourseWorkflows::WorkflowTagMapping)  # valid in ABD
FactoryBakery.bake(DiscourseWorkflows::WorkflowVersion)  # valid in ABD
FactoryBakery.bake(DismissedTopicUser)  # valid in ABD
FactoryBakery.bake(DoNotDisturbTiming)  # valid in ABD
FactoryBakery.bake(Draft)  # valid in ABD
FactoryBakery.bake(DraftSequence)  # valid in ABCD
FactoryBakery.bake(Dsa::Notice)  # valid in ABD
FactoryBakery.bake(DsaStatementOfRecord)  # valid in ABCD
FactoryBakery.bake(EmailChangeRequest)  # valid in ABD
FactoryBakery.bake(EmailLog)  # valid in ABD
FactoryBakery.bake(EmailLoginCode)  # valid in ABCD
FactoryBakery.bake(EmailToken)  # valid in ABD
FactoryBakery.bake(EmbeddableHost)  # valid in AB
FactoryBakery.bake(EmbeddableHostTag)  # valid in ABD
FactoryBakery.bake(ExternalUploadStub)  # valid in ABD
FactoryBakery.bake(Flag)  # valid in ABCD
FactoryBakery.bake(GivenDailyLike)  # valid in ABD
FactoryBakery.bake(GroupArchivedMessage)  # valid in ABD
FactoryBakery.bake(GroupAssociatedGroup)  # valid in ABD
FactoryBakery.bake(GroupCategoryNotificationDefault)  # valid in ABD
FactoryBakery.bake(GroupCustomField)  # valid in ABD
FactoryBakery.bake(GroupMention)  # valid in ABD
FactoryBakery.bake(GroupRequest)  # valid in ABD
FactoryBakery.bake(GroupTagNotificationDefault)  # valid in ABD
FactoryBakery.bake(GroupUser)  # valid in ABD
FactoryBakery.bake(HABTM_Categories)  # valid in AB
FactoryBakery.bake(HABTM_Groups)  # valid in AB
FactoryBakery.bake(HABTM_Tags)  # valid in AB
FactoryBakery.bake(HABTM_WebHookEventTypes)  # valid in AB
FactoryBakery.bake(HABTM_WebHooks)  # valid in AB
FactoryBakery.bake(IgnoredUser)  # valid in ABD
FactoryBakery.bake(IncomingDomain)  # valid in ABCD
FactoryBakery.bake(IncomingEmail)  # valid in ABD
FactoryBakery.bake(IncomingReferer)  # valid in ABCD
FactoryBakery.bake(InferredConcept)  # valid in AB
FactoryBakery.bake(Invite)  # valid in AB
FactoryBakery.bake(InvitedGroup)  # valid in ABD
FactoryBakery.bake(InvitedUser)  # valid in ABD
FactoryBakery.bake(JavascriptCache)  # valid in ABD
FactoryBakery.bake(LinkedTopic)  # valid in ABD
FactoryBakery.bake(Live::CoPresence)  # valid in AB
FactoryBakery.bake(Live::Recording)  # valid in ABD
FactoryBakery.bake(Live::Room)  # valid in AB
FactoryBakery.bake(Live::RoomMembership)  # valid in ABD
FactoryBakery.bake(Live::Session)  # valid in ABD
FactoryBakery.bake(LlmCreditAllocation)  # valid in ABD
FactoryBakery.bake(LlmFeatureCreditCost)  # valid in ABD
FactoryBakery.bake(LlmModel)  # valid in AB
FactoryBakery.bake(McpAuditLog)  # valid in ABD
FactoryBakery.bake(McpOauthAccessToken)  # valid in ABD
FactoryBakery.bake(McpOauthAuthorization)  # valid in ABD
FactoryBakery.bake(McpOauthAuthorizationCode)  # valid in ABCD
FactoryBakery.bake(McpOauthAuthorizationScope)  # valid in ABCD
FactoryBakery.bake(McpOauthRefreshToken)  # valid in ABCD
FactoryBakery.bake(McpPrimitive)  # valid in ABCD
FactoryBakery.bake(MiniScheduler::Stat)  # valid in ABCD
FactoryBakery.bake(ModelAccuracy)  # valid in ABCD
FactoryBakery.bake(MutedUser)  # valid in ABD
FactoryBakery.bake(Notification)  # valid in ABD
FactoryBakery.bake(Oauth2UserInfo)  # valid in ABD
FactoryBakery.bake(OnceoffLog)  # valid in ABCD
FactoryBakery.bake(OptimizedImage)  # valid in ABD
FactoryBakery.bake(OptimizedVideo)  # valid in ABD
FactoryBakery.bake(Permalink)  # valid in AB
FactoryBakery.bake(PluginStoreRow)  # valid in ABCD
FactoryBakery.bake(Poll)  # valid in ABD
FactoryBakery.bake(PollOption)  # valid in ABD
FactoryBakery.bake(PollVote)  # valid in ABD
FactoryBakery.bake(PostActionType)  # valid in ABCD
FactoryBakery.bake(PostDetail)  # valid in ABD
FactoryBakery.bake(PostRevision)  # valid in ABD
FactoryBakery.bake(PostStat)  # valid in ABD
FactoryBakery.bake(PostTiming)  # valid in ABD
FactoryBakery.bake(ProblemCheckTracker)  # valid in ABCD
FactoryBakery.bake(PublishedPage)  # valid in ABD
FactoryBakery.bake(PushSubscription)  # valid in ABD
FactoryBakery.bake(RagDocumentFragment)  # valid in ABD
FactoryBakery.bake(RagDocumentSource)  # valid in ABD
FactoryBakery.bake(RedeliveringWebhookEvent)  # valid in ABCD
FactoryBakery.bake(RemoteTheme)  # valid in ABD
FactoryBakery.bake(Reviewable::UnknownType)  # valid in AB
FactoryBakery.bake(ReviewableAiChatMessage)  # valid in AB
FactoryBakery.bake(ReviewableAiPost)  # valid in AB
FactoryBakery.bake(ReviewableAiToolAction)  # valid in AB
FactoryBakery.bake(ReviewableClaimedTopic)  # valid in ABD
FactoryBakery.bake(ReviewableFlaggedPost)  # valid in AB
FactoryBakery.bake(ReviewableLiveUser)  # valid in AB
FactoryBakery.bake(ReviewablePost)  # valid in AB
FactoryBakery.bake(ReviewablePostVotingComment)  # valid in AB
FactoryBakery.bake(ReviewableQueuedPost)  # valid in AB
FactoryBakery.bake(ReviewableUser)  # valid in AB
FactoryBakery.bake(ScreenedEmail)  # valid in ABCD
FactoryBakery.bake(ScreenedIpAddress)  # valid in ABCD
FactoryBakery.bake(ScreenedUrl)  # valid in ABCD
FactoryBakery.bake(SearchLog)  # valid in ABD
FactoryBakery.bake(SharedDraft)  # valid in ABD
FactoryBakery.bake(ShelvedNotification)  # valid in ABD
FactoryBakery.bake(SidebarSection)  # valid in ABD
FactoryBakery.bake(SidebarSectionLocalization)  # valid in ABD
FactoryBakery.bake(SidebarUrl)  # valid in ABCD
FactoryBakery.bake(SidebarUrlLocalization)  # valid in ABCD
FactoryBakery.bake(SilencedAssignment)  # valid in ABD
FactoryBakery.bake(SingleSignOnRecord)  # valid in ABD
FactoryBakery.bake(SiteSetting)  # valid in ABCD
FactoryBakery.bake(SiteSettingGroup)  # valid in AB
FactoryBakery.bake(Sitemap)  # valid in ABCD
FactoryBakery.bake(StylesheetCache)  # valid in ABCD
FactoryBakery.bake(Tag)  # valid in AB
FactoryBakery.bake(TagGroup)  # valid in ABD
FactoryBakery.bake(TagGroupMembership)  # valid in ABD
FactoryBakery.bake(TagGroupPermission)  # valid in ABD
FactoryBakery.bake(TagLocalization)  # valid in ABD
FactoryBakery.bake(TagSearchData)  # valid in ABD
FactoryBakery.bake(TagUser)  # valid in ABD
FactoryBakery.bake(Theme)  # valid in AB
FactoryBakery.bake(ThemeField)  # valid in ABD
FactoryBakery.bake(ThemeModifierSet)  # valid in ABD
FactoryBakery.bake(ThemeSetting)  # valid in ABD
FactoryBakery.bake(ThemeSettingsMigration)  # valid in ABD
FactoryBakery.bake(ThemeSiteSetting)  # valid in ABD
FactoryBakery.bake(ThemeSvgSprite)  # valid in ABD
FactoryBakery.bake(ThemeTranslationOverride)  # valid in ABD
FactoryBakery.bake(TopTopic)  # valid in ABD
FactoryBakery.bake(Topic)  # valid in AB
FactoryBakery.bake(TopicAllowedGroup)  # valid in ABD
FactoryBakery.bake(TopicAllowedUser)  # valid in ABD
FactoryBakery.bake(TopicCustomField)  # valid in ABD
FactoryBakery.bake(TopicGroup)  # valid in ABD
FactoryBakery.bake(TopicHotScore)  # valid in ABD
FactoryBakery.bake(TopicInvite)  # valid in ABD
FactoryBakery.bake(TopicLocalization)  # valid in ABD
FactoryBakery.bake(TopicSearchData)  # valid in ABD
FactoryBakery.bake(TopicTag)  # valid in ABD
FactoryBakery.bake(TopicThumbnail)  # valid in ABD
FactoryBakery.bake(TopicUser)  # valid in ABD
FactoryBakery.bake(TopicViewStat)  # valid in ABD
FactoryBakery.bake(TranslationOverride)  # valid in ABCD
FactoryBakery.bake(UnsubscribeKey)  # valid in ABD
FactoryBakery.bake(UpcomingChangeEvent)  # valid in ABD
FactoryBakery.bake(Upload)  # valid in AB
FactoryBakery.bake(UploadReference)  # valid in ABD
FactoryBakery.bake(User)  # valid in AB
FactoryBakery.bake(UserAction)  # valid in ABD
FactoryBakery.bake(UserApiKey)  # valid in ABD
FactoryBakery.bake(UserApiKeyClient)  # valid in ABCD
FactoryBakery.bake(UserApiKeyClientScope)  # valid in ABCD
FactoryBakery.bake(UserApiKeyScope)  # valid in ABCD
FactoryBakery.bake(UserArchivedMessage)  # valid in ABD
FactoryBakery.bake(UserAssociatedAccount)  # valid in ABD
FactoryBakery.bake(UserAssociatedGroup)  # valid in ABD
FactoryBakery.bake(UserAuthToken)  # valid in ABD
FactoryBakery.bake(UserAuthTokenLog)  # valid in ABD
FactoryBakery.bake(UserAvatar)  # valid in ABD
FactoryBakery.bake(UserCustomField)  # valid in ABD
FactoryBakery.bake(UserEmail)  # valid in ABD
FactoryBakery.bake(UserExport)  # valid in ABD
FactoryBakery.bake(UserField)  # valid in ABCD
FactoryBakery.bake(UserFieldOption)  # valid in ABCD
FactoryBakery.bake(UserHistory)  # valid in ABD
FactoryBakery.bake(UserIpAddressHistory)  # valid in ABD
FactoryBakery.bake(UserOpenId)  # valid in ABD
FactoryBakery.bake(UserOption)  # valid in ABD
FactoryBakery.bake(UserPassword)  # valid in A
FactoryBakery.bake(UserProfile)  # valid in ABD
FactoryBakery.bake(UserRequiredFieldsVersion)  # valid in ABCD
FactoryBakery.bake(UserSearchData)  # valid in ABD
FactoryBakery.bake(UserSecondFactor)  # valid in ABD
FactoryBakery.bake(UserSecurityKey)  # valid in ABD
FactoryBakery.bake(UserStat)  # valid in ABD
FactoryBakery.bake(UserUpload)  # valid in ABD
FactoryBakery.bake(UserVisit)  # valid in ABD
FactoryBakery.bake(UserVisitDailyRollup)  # valid in ABCD
FactoryBakery.bake(UserWarning)  # valid in ABD
FactoryBakery.bake(WatchedWord)  # valid in ABCD
FactoryBakery.bake(WebCrawlerRequest)  # valid in ABCD
FactoryBakery.bake(WebHookEvent)  # valid in AB
FactoryBakery.bake(WebHookEventType)  # valid in ABCD
FactoryBakery.bake(WebHookEventTypesHook)  # valid in ABCD
FactoryBakery.bake(WebHookEventsDailyAggregate)  # valid in ABCD
```

---

## 3. Needs a definition

87 models failed automatic pass A. Definitions were added for the root causes
below; 39 of those models now bake valid in pass A, taking the defined round to
366/414. The complete final file is copied to
`docs/reports/smoke/20261119-final-discourse-definitions.rb`.

| Model(s) | App rule the gem cannot infer (source) | Definition |
|---|---|---|
| `UserEmail` | Discourse sets `belongs_to_required_by_default = false`; `User → primary_email → UserEmail → User` cycle | `user { nil }` |
| `User` | username must be alphanumeric ≤20 chars; `has_one :primary_email` needs a real address; `secure_identifier` has a DB unique index that generated values collide with | random literal username, password, random hex `secure_identifier`, real `UserEmail` in `primary_email` |
| `Category` | hex colour regex `\A(\h{6}|\h{3})\z` (`category.rb`); `emoji_exists` requires a real Emoji (`category.rb:418`) | literal `color`/`text_color`, `emoji { nil }` |
| `AccessControlList`, `AiSummary`, `Assignment` | required polymorphic `target` / `assigned_to` no discoverable concrete target | `association …, factory: Group/Topic/User` with nil FK/type columns |
| `AiAgent` | `examples` must be an array | `examples { [] }` |
| `AdPlugin::AdImpression` | `ad_type` enum: non-house ads must have a nil house-ad FK (`ad_plugin` model) | `ad_type { :adsense }`, nil FK |
| `AiMcpServer` | `url` must resolve to a publicly accessible address | literal `https://discourse.org` |
| `Blog::Path`, `Blog::Publication` | slug/path format rule | literal `/smoke-…` paths |
| `UserStatus` | `emoji_exists` (`user_status.rb:17-19`) | `emoji { 'smile' }`, `ends_at { nil }` |
| `Chat::Message`, `Chat::NullMessage` | `normalizes :blocks` iterates an array of hashes (`chat/message.rb:122-135`); `JsonFiller` emits a Hash | `blocks { [] }` |
| `CompletionPrompt` | `each_message_length` indexes `msg["content"]` over an array (`completion_prompt.rb:61-66`) | `messages { [] }` |
| `Chat::MessageSearchData` | legacy `"ChatMessage"` class name mapped to `Chat::Message` by the app (`chat/message.rb:137`); gem mapper cannot constantize it | `association :chat_message, factory: Chat::Message` (attempted; mapper still fails — §4) |
| `Group` | name format + trust-level inclusion | literal name, `trust_level { 0 }` |
| `WebHook` | event types presence unless wildcard (`web_hook.rb:19`) | `wildcard_web_hook { true }` + literal payload URL/content type/status |
| `WatchedWordGroup`, `FormTemplate` | watched-words presence / template must be valid YAML | attempted (`watched_words { [] }`, YAML literal) — still invalid (§4) |

Full definition code (identical to the copied file):

```ruby
# frozen_string_literal: true
require 'securerandom'
require 'factory_bakery/attachments'

FactoryBakery.define(UserEmail) { user { nil } }

FactoryBakery.define(User) do
  username { "fb_#{SecureRandom.hex(5)}" }
  password { 'SmokePass123!' }
  secure_identifier { SecureRandom.hex(12) }
  primary_email do
    FactoryBakery.bake(UserEmail, email: "fb_#{SecureRandom.hex(5)}@example.com", primary: true)
  end
end

FactoryBakery.define(Category) do
  color { 'FF0000' }
  text_color { '00FF00' }
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

FactoryBakery.define(AiAgent) { examples { [] } }

FactoryBakery.define(AdPlugin::AdImpression) do
  ad_type { :adsense }
  ad_plugin_house_ad_id { nil }
end

FactoryBakery.define(AiMcpServer) { url { 'https://discourse.org' } }

FactoryBakery.define(Assignment) do
  assigned_to_id { nil }
  assigned_to_type { nil }
  association :assigned_to do |_owner|
    FactoryBakery.bake(User)
  end
end

FactoryBakery.define(Blog::Path) { path { "/smoke-path-#{SecureRandom.hex(6)}" } }
FactoryBakery.define(Blog::Publication) { path { "/smoke-pub-#{SecureRandom.hex(6)}" } }

FactoryBakery.define(UserStatus) do
  emoji { 'smile' }
  ends_at { nil }
end

FactoryBakery.define(Chat::Message) { blocks { [] } }
FactoryBakery.define(Chat::NullMessage) { blocks { [] } }
FactoryBakery.define(CompletionPrompt) { messages { [] } }

FactoryBakery.define(Chat::MessageSearchData) do
  association :chat_message, factory: Chat::Message
end

FactoryBakery.define(Group) do
  name { "smoke_group_#{SecureRandom.hex(4)}" }
  trust_level { 0 }
end

FactoryBakery.define(WebHook) do
  payload_url { 'https://example.com/webhook' }
  content_type { 'application/json' }
  last_delivery_status { 'inactive' }
  wildcard_web_hook { true }
end

FactoryBakery.define(WatchedWordGroup) { watched_words { [] } }
FactoryBakery.define(FormTemplate) { template { "---\n{}\n" } }
```

---

## 4. Still failing

Pass A has 48 failures, pass B 31, pass C 285, pass D 101 with the final
definitions. The pass-A residuals are app-specific rules and gem defects;
the full per-model list is in `final-defined.jsonl`.

### Pass A (48 models)

| Group | Count | Models | Root cause / class |
|---|---:|---|---|
| `RateLimiter::LimitExceeded` | 8 | `DiscourseSolved::SharedIssue`, `DiscourseSolved::SolvedTopic`, `DiscourseSolved::TopicAnswer`, `DiscourseTemplates::UsageCount`, `InferredConceptTopic`, `NestedTopic`, `TopicTimer`, `TopicViewItem` | Baked parents trip Discourse's real rate limiter; **app-specific** (gem triggers it via legitimate parent builds) |
| `Topic/User can't be blank` | 7 | `IncomingLink`, `InferredConceptPost`, `Live::Invite`, `Post`, `PostReplyKey`, `PostVotingComment`, `PostVotingCommentCustomField` | Cross-field @mention/topic/user rules; **app-specific**, needs explicit associations |
| `NOT NULL require_confirmation` | 3 | `Boards::BoardHistory`, `Boards::Card`, `Boards::CardHistory` | NOT NULL column with no heuristic-safe value; **gem defect** (NOT NULL column left nil when parent is saved) |
| `bot?` on nil | 2 | `Chat::Message`, `Chat::NullMessage` | App validator dereferences an optional association; **app-specific** |
| Polymorphic / class resolution | 2 | `Chat::MessageSearchData`, `SharedAiConversation` | Mapper cannot constantize `"ChatMessage"` / discover a target; **gem defect** (§5) |
| Other singles | 26 | `AdminDashboardReport`, `AiModerationSetting`, `AiToolSecretBinding`, `Bookmark`, `Chat::Channel`, `DiscourseAutomation::Field`, `DiscourseChatIntegration::Channel`, `DiscourseChatIntegration::Rule`, `FormTemplate`, `LlmCreditDailyUsage`, `LlmQuota`, `LlmQuotaUsage`, `McpGroupScope`, `McpOauthClient`, `PostReply`, `PostVotingVote`, `Reviewable`, `ReviewableNote`, `SidebarSectionLink`, `SiteSettingLocalization`, `TopicLink`, `TopicLinkClick`, `UserBadge`, `UserNotificationSchedule`, `UserProfileView`, `WatchedWordGroup` | Mix of registry values, enum/inclusion rules, custom validators, uniqueness collisions; **app-specific** with a few **gem gaps** (JSON shape, raw-FK reuse) |

### Pass B (31 models)

Dominated by `FactoryBakery::Error: … validates foreign key …, but strategy:
:reuse found no row to reuse under bake` (6 models: `Boards::CardHistory`,
`DiscourseSolved::TopicAnswer`, `LlmQuotaUsage`, `ReviewableNote`,
`TopicLinkClick`, `UserBadge`) — a **gem defect** in the raw-FK `:reuse`
contract — plus the same app-specific pass-A residuals.

### Passes C & D

`:all` mode over-builds the graph: 145 pass-C failures are
`NoMethodError: undefined method '+' for nil` from app serializers fed
Hash-shaped JSON, 28 hit "Email and domain fields are not allowed", 21 are
serialization mismatches, 20 `NoMethodError: trust_level for Guard`, 14
polymorphic/class resolution failures, 13 cycles; pass D adds 23 class-resolution
and 11 `Reviewable notes is invalid` failures. All are **gem defects** in `:all`
mode (unbounded auto-build, JSON shape, HABTM join models, cycles) with
app-specific validators as the trigger. No application code was edited.

---

## 5. Gem defects / improvement opportunities (ranked by models affected)

1. **`:all` mode over-builds association graphs against real apps** —
   285 failures in pass C and 101 in pass D with definitions; 269 of the
   automatic pass-C failures alone were the single `User#primary_email`
   cascade (`Primary email can't be blank`). A definition can tame the root
   model, but arbitrary nested nodes still get built with unsatisfiable
   app-specific rules. *Improvement:* make `:all` bounded by validity, or expose
   a global "skip these associations everywhere" escape hatch.
2. **JSON column filler always emits a Hash** —
   `lib/factory_bakery/attribute_fillers/json_filler.rb:5,48-58`. Apps with
   array-shaped JSON columns break: `Chat::Message#blocks`,
   `Chat::NullMessage#blocks`, `CompletionPrompt#messages`
   (`chat/message.rb:127-133`, `completion_prompt.rb:61-66`), plus ~21
   `ActiveRecord::SerializationTypeMismatch` failures in pass C. *Improvement:*
   infer array shape from a normalizer/serializer or allow `json_array: true`.
3. **Reflection/class resolution ignores app mappings** — `Chat::MessageSearchData`
   declares `belongs_to :chat_message`; the app maps `"ChatMessage"` to
   `Chat::Message` via `self.polymorphic_class_mapping`
   (`plugins/chat/app/models/chat/message.rb:137`). The gem's
   `PolymorphicTargetDiscovery#constantize` (line 136-140) only calls
   `Object.const_get`, so it raises `NameError: Missing model class ChatMessage`;
   the same error cascades to 14 pass-C / 23 pass-D models. `SharedAiConversation#target`
   has no discoverable target. *Improvement:* consult app class mappings /
   namespaced reflections before giving up.
4. **`secure_identifier` uniqueness collisions among sibling records** — 8
   models in automatic pass A (`PostCustomField`, `PostPolicy`,
   `PostVotingComment`, `ReviewableHistory`, `ReviewableScore`,
   `SidebarSectionLink`, `InferredConceptPost`, …) fail with
   `PG::UniqueViolation: index_users_on_secure_identifier`. `UniquenessEnforcer`
   (`lib/factory_bakery/uniqueness_enforcer.rb:27-39`) only queries the DB, not
   other unsaved records in the same graph, and the generic word filler returns
   a bare word (`placeat`). *Improvement:* track generated values per graph and
   use identifier-shaped entropy for `*_identifier` names.
5. **Raw-FK `:reuse` misses under `bake`** — 6 models in pass B and 7 in pass D
   raise `FactoryBakery::Error: … strategy: :reuse found no row to reuse under
   bake`. Documented, but it makes `:reuse` unusable for a read-only smoke run.
6. **Cyclic association detection in `:all` mode** — 13 pass-C / 1 pass-D models
   (`Blog::Revision`, `Boards::Column`, `MovedPost`, `WebHookEvent`, …) raise
   `CyclicAssociationError` for optional self/ reciprocal edges that a minimal
   definition cannot always suppress on nested nodes.
7. **HABTM / join models cannot be built in `:all` mode** —
   `can't write unknown attribute 'left_side_id'/'target_user_id'/'email_log_id'`
   for `HABTM_Groups`, `HABTM_Tags`, `HABTM_WebHooks` and others (4 pass C, 8 pass D).
8. **Rate-limiter side effects** — 8 pass-A models raise
   `RateLimiter::LimitExceeded` because baked parents perform real writes;
   not a correctness bug in the gem, but a full-boot smoke hazard worth
   documenting.
9. **Custom-validator columns filled with invalid values in `:all` mode** —
   trust-level enums, `AiModerationSetting` setting type, `McpGroupScope` scope,
   `McpOauthClient` redirect URIs and `UserNotificationSchedule` day windows
   all fail when optional columns are filled indiscriminately.

Outbound network was off for every bake. No HTTP/connection errors were
observed in the Discourse run — the gem never fetched a URL. All app-side
failures above are validation/state problems, not network fetches.
