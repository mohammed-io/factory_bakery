> The `factory-bakery-diagnostics` skill keeps an identical copy of everything below this line at `skills/factory-bakery-diagnostics/references/diagnostics.md`.

# Diagnostics catalog

Every failure kind a bake can produce, with the exact message, the cause, where to look, the smallest fix, and a real example when one exists. Anchors are stable. `bin/rails factory_bakery:doctor` prints a GitHub link to the matching anchor for each failing model.

Conventions:

- **Gem** means a file under `lib/factory_bakery/`. **App** means your code.
- Messages are quoted from `lib/`. `X`, `Y`, `name` stand for your class, association and attribute names. Messages marked *(Rails)* come from ActiveRecord, not from this gem.
- "Smallest fix" ranks: a call-site override, a definition line, `persist:`, `with:`, `skip`, `strategy: :fresh`, then a gem bug report. See [the ladder](#choosing-the-fix).
- Mastodon and Discourse examples come from `docs/reports/smoke/20261119-final-*-definitions.rb`.

## Index by message

| Message contains | Anchor |
| --- | --- |
| `No factory is registered for` | [#unregistered-factory](#unregistered-factory) |
| `Unsupported bake target` | [#unsupported-bake-target](#unsupported-bake-target) |
| `Could not resolve a class for factory` | [#unresolvable-factory-class](#unresolvable-factory-class) |
| `Trait ... is not declared for` | [#unknown-trait](#unknown-trait) |
| `requires the associations plugin` | [#association-plugin-not-loaded](#association-plugin-not-loaded) |
| `skip is the attribute-omission DSL method` | [#skip-misuse](#skip-misuse) |
| `bake nesting exceeded max_bake_depth` | [#nesting-too-deep](#nesting-too-deep) |
| `declare one side (e.g. ... { nil })` | [#cyclic-association](#cyclic-association) |
| `has no association :` | [#unknown-association](#unknown-association) |
| `uninitialized constant` naming a `belongs_to` class | [#missing-association-class](#missing-association-class) |
| `left X#y_remote_url blank on purpose` *(WARN log)* | [#remote-url-left-blank](#remote-url-left-blank) |
| `is not supported; assign via an attribute block` | [#unsupported-association-shape](#unsupported-association-shape) |
| `unknown association option(s)`, `count:`, `persist:`, `with:` ArgumentErrors | [#association-option-errors](#association-option-errors) |
| `has a polymorphic association` | [#polymorphic-factory-required](#polymorphic-factory-required) |
| `is incompatible with` | [#factory-incompatible](#factory-incompatible) |
| `is a required polymorphic association; no target discovered` | [#no-polymorphic-target-discovered](#no-polymorphic-target-discovered) |
| `none of ... could be baked` | [#polymorphic-targets-all-failed](#polymorphic-targets-all-failed) |
| `strategy: :reuse_non_unique ...` | [#reuse-strategy-errors](#reuse-strategy-errors) |
| `invalid associations mode / strategy`, `must be a non-negative Integer` | [#configuration-errors](#configuration-errors) |
| `bake! did not persist all generated records` | [#incomplete-persistence](#incomplete-persistence) |
| `is read-only (readonly? is true` | [#read-only-target](#read-only-target) |
| `cannot be inserted: its required` | [#fk-parent-cannot-be-inserted](#fk-parent-cannot-be-inserted) |
| `could not generate a unique value for` | [#unique-value-collisions](#unique-value-collisions) |
| `could not generate a format-compliant value` / `JSON value` | [#format-exhaustion](#format-exhaustion) |
| `could not generate a value satisfying the numeric constraints` | [#numeric-constraint-exhaustion](#numeric-constraint-exhaustion) |
| `could not generate a value ... that satisfies exclusion` | [#exclusion-exhaustion](#exclusion-exhaustion) |
| `length :… resolved to` | [#length-resolution-error](#length-resolution-error) |
| `length :… raised` | [#length-option-raised](#length-option-raised) |
| `:in proc raised` | [#inclusion-proc-raised](#inclusion-proc-raised) |
| `(FactoryBakery also tried ... construction)` | [#construction-failed](#construction-failed) |
| `no bundled attachment fixture matches` | [#attachment-fixture-missing](#attachment-fixture-missing) |
| `factory_bakery/sequel requires the sequel gem` | [#sequel-gem-missing](#sequel-gem-missing) |
| `no associations on X; it is not ActiveRecord` | [#sequel-associations-unsupported](#sequel-associations-unsupported) |
| `Validation failed: ... must exist` *(Rails)* | [#must-exist-error](#must-exist-error) |
| `Validation failed: ...` a validator reading a parent's id | [#id-reading-custom-validator](#id-reading-custom-validator) |
| `has already been taken` after a reuse | [#reuse-picks-owners-own-parent](#reuse-picks-owners-own-parent) |
| `Items is invalid` with several literal children | [#literal-override-uniqueness](#literal-override-uniqueness) |
| `PG::UniqueViolation` / `RecordNotUnique` on a has_one | [#has-one-created-by-callback](#has-one-created-by-callback) |
| `NotNullViolation`, `InvalidForeignKey` *(Rails)* | [#db-only-constraints](#db-only-constraints) |
| `Chosen at random:` or `FactoryBakery could not produce a valid` after a validation error | [#random-value-rejected-by-app-rule](#random-value-rejected-by-app-rule) |
| `Static attributes are unsupported` | [#factory-attribute-errors](#factory-attribute-errors) |
| `Cyclic attribute dependency` | [#factory-attribute-errors](#factory-attribute-errors) |
| `to declare a value` (`Use name { ... }`, `Use add_attribute(:x) { ... }`, or `Use admin { ... }` when a trait calls another trait by bare name) | [#factory-attribute-errors](#factory-attribute-errors) |
| `FACTORY_BAKERY_SEED must be an integer`, `FactoryBakery.seed must be an Integer` | [#configuration-errors](#configuration-errors) |
| A subclass bakes with its parent's values | [#subclass-uses-parent-definition](#subclass-uses-parent-definition) |
| Record invalid, validator reads a registry or setting | [#registry-and-inclusion-lists](#registry-and-inclusion-lists) |
| Record invalid, a time rule | [#time-relative-validations](#time-relative-validations) |
| A text column parsed as JSON or YAML | [#structured-text-columns](#structured-text-columns) |
| Silent: wrong value, no error | [#silent-failures](#silent-failures) |

## Choosing the fix

Reproduce first, with the seed the failure printed (`Seed N from <source>. Reproduce: <command>`): replay the failing spec with `rspec --seed N` (Minitest: `bin/rails test --seed N`), or start a fresh process with `FACTORY_BAKERY_SEED=N RAILS_ENV=test` and replay the printed root ordinal — the earlier bakes of that class, then bake #N itself inside the rollback wrappers: the original verb, target, traits and overrides, identical to the call that failed. Changing ENV after seed resolution has no effect: the seed resolves on first use and is memoized, including on an explicit `FactoryBakery.seed` read. Inside the rollback wrappers — `Model.transaction(requires_new: true) { ...; raise ActiveRecord::Rollback }` for the failing model's own connection pool, plus the same wrapper around every other pool the graph writes to (a wrapper covers one pool; `bake!` commits, and plain `bake` can still insert raw-FK parents; omit a wrapper only when the whole call, declarations and callbacks included, performs no database writes); for a Sequel model, `model.db.transaction(rollback: :always)` — replay bake #N with the verb that failed. A bake failure: `FactoryBakery.bake(Model)`; when a record returns invalid, call `FactoryBakery.explain(record)` (it runs `valid?`) and read `.errors.full_messages`. A bake! failure: `FactoryBakery.bake!(Model)`; read the exception whenever the original verb raises (a cyclic attribute declaration raises before returning from either verb). Never add a plain bake between the warm-up bakes and the bake! replay (it advances the bake ordinal). Run any plain-bake comparison in a separate process, after the same N-1 warm-up bakes, inside the rollback wrappers. See [Randomness](guide/configuration.md#randomness).

| The cause is | Smallest fix |
| --- | --- |
| A test needs a specific value | A call-site override |
| A rule only your app knows (registry, setting, cross-record) | One definition line |
| A validator reads a parent's **id** | `association :x, persist: true` |
| The child needs a specific attribute on a built parent | `association :x, with: { ... }` |
| A setter or edge has a side effect or cycles | `skip :x` |
| An edge picked the wrong existing row | `strategy: :fresh` on that edge |
| A declared validator the gem should handle is mishandled | A gem bug report with a minimal repro |

Never change the model, its validations or the schema to make baking easier. That is a one-way door the user must approve.

---

## Definition and DSL errors

### unregistered-factory

- **Message:** `No factory is registered for :nothing`
- **Class:** `FactoryBakery::Error`
- **Cause:** `bake(:nothing)` with a symbol that no `define(:nothing, ...)` registered. Symbols never fall back to constantizing here.
- **Where to look:** gem `BakeryBuilder.resolve`. App: the definition files, and `FactoryBakery.definition_paths`.
- **Fix:** Register it (`FactoryBakery.define(:nothing, klass: X)`), or bake the class (`bake(X)`). In Rails, check the file is under the loaded directory.
- **Often caused by:** definitions in `spec/factories` that factory_bot owns while FactoryBakery looks in `spec/bakery`.

### unsupported-bake-target

- **Message:** `Unsupported bake target "User"; pass a class or a registered symbol`
- **Cause:** A String (or other object) was passed to `bake`.
- **Fix:** Pass the class: `bake(User)`.

### unresolvable-factory-class

- **Message:** `Could not resolve a class for factory :ghost (tried "Ghost"); pass klass: when defining it`
- **Cause:** A symbol factory without `klass:` whose camelized name is not a constant. Namespaced models need `klass:`.
- **Where to look:** gem `BakeryBuilder.constantize`.
- **Fix:** `FactoryBakery.define(:ghost, klass: Ns::Ghost) { ... }`. The failure is not cached, so a later bake can succeed once the constant exists.

### unknown-trait

- **Message:** `Trait :nope is not declared for User`
- **Cause:** The trait is absent from **the definition the bake target uses**: its own, or its nearest ancestor class's when it has none (traits are inherited with it). Also raised for a class with no definition of its own or from an ancestor, for a trait forwarded to a child (`association :author, :admin`) the child's definition lacks. In `association :author, :admin`, `:admin` is a trait on the **target's** definition.
- **Not this error:** a trait cannot call another trait by bare name. `trait :super_admin do admin end` raises `Use admin { ... } to declare a value, or skip :admin` ([factory-attribute-errors](#factory-attribute-errors)), because the bare name reads as an attribute declaration.
- **Fix:** Declare the trait in that class's definition, or fix the name. To combine traits, repeat the lines, or pass both at the call site.

### association-plugin-not-loaded

- **Message:** `` `association` requires the associations plugin: require 'factory_bakery/associations' ``
- **Cause:** `association :x` is used without the plugin.
- **Fix:** Rails: `config.factory_bakery.associations = { mode: :required_only }`. Otherwise `require 'factory_bakery/associations'`.
- **Note:** If something calls `FactoryBakery.reset_plugins!`, the plugin is removed and this error returns.

### skip-misuse

- **Message:** `skip is the attribute-omission DSL method; use add_attribute(:skip) { ... } to declare a real attribute named skip`
- **Cause:** `skip` was given a block, or no names.
- **Fix:** `skip :name, :other`. For a real attribute called `skip`: `add_attribute(:skip) { ... }`.

### duplicate-plugin-dsl

- **Message:** `DSL method :downcase is already provided by another plugin`
- **Cause:** Two registered plugins define the same DSL method.
- **Where to look:** gem `PluginRegistry.register`. App: the plugins you register.
- **Fix:** Rename one DSL method.

### no-plugin-dsl-call-in-progress

- **Message:** `No plugin DSL call is in progress`
- **Cause:** A plugin called `record_plugin_declaration` outside one of its own DSL methods, or from a method that is not defined directly on its `dsl_module`.
- **Fix:** Define the method on the DSL module itself. See [Plugins](guide/plugins.md).

### nesting-too-deep

- **Message:** `bake nesting exceeded max_bake_depth (10): User -> User -> User`
- **Class:** `FactoryBakery::NestingTooDeepError`
- **Cause:** Nested bakes exceed `FactoryBakery.max_bake_depth`. A class that repeats in the path usually means a declaration block that bakes the class it belongs to (or a parent that bakes its child). A path with no repetition is a deep graph, not a loop.
- **Where to look:** The path in the message shows where the depth limit hit. Check it for a repeated class before calling it a loop. App: the definition for the first repeated class.
- **Fix:** If the path repeats, break the loop (`skip :child`, pass the owner). Raise `max_bake_depth` only for a legitimately deep graph.

### configuration-errors

- **Messages (`ArgumentError`):**
  - `invalid associations mode :bogus; expected one of [:none, :required_only, :all]`
  - `invalid associations strategy :reuse; expected one of [:fresh, :reuse_non_unique]`
  - `max_depth must be a non-negative Integer, got -1` (also `default_count`)
  - `eager_load must be true or false, got "yes"`
  - `unknown associations scope option :foo; expected one of [:mode, :strategy, :max_depth, :default_count, :eager_load]`
  - `unknown associations config option :x; expected one of [...]`
  - `associations config must be a Hash, true, false or a mode symbol, got ...`
  - `fill_optional must be true, false, or an array of attribute names, got "true"`
  - `FACTORY_BAKERY_SEED must be an integer, got "abc"`
  - `FactoryBakery.seed must be an Integer, a callable returning an Integer, or nil, got "x"`
  - `FactoryBakery.seed callable must return an Integer, got "x"` (also `RSpec seed must be an Integer, got ...`, `Minitest seed must be an Integer, got ...`)
- **Where to look:** gem `associations/configuration.rb`, `associations/rail_config.rb`, `FactoryBakery.normalize_fill_optional`, `seed.rb`. App: `config/application.rb`, initializers, `Associations.with(...)` calls, the `FACTORY_BAKERY_SEED` environment variable.
- **Fix:** Use a listed value. `strategy: :reuse` was renamed `:reuse_non_unique` with no alias. A seed is a base-10 Integer, or a callable returning one. `nil` clears the `seed =` setting.

---

## Association errors

### unknown-association

- **Message:** `Post has no association :nope`. It may end with ` (could not be introspected: ...)` when the class's reflections could not be read.
- **Cause:** `association :nope` names no reflection of the owner. Checked at bake time.
- **Fix:** Fix the name. For the "could not be introspected" suffix, the model has an unloadable sibling association: look at the named failure (a stale `class_name`).

### missing-association-class

- **Message:** `NameError: uninitialized constant ChatMessage` (or `Owner#edge: ...`) while baking a model whose `belongs_to` names a class that does not exist.
- **Cause:** The declared `class_name` has no constant. FactoryBakery first asks the owner's `polymorphic_class_for` (an app mapping such as Discourse's `"ChatMessage"` to `Chat::Message`), then reads the database foreign key constraint on the edge's column and uses the single model stored in the referenced table. It assigns the foreign key column directly, because the association writer cannot run. The error surfaces only when neither finds a class (no mapping and no foreign key constraint, or several models share the referenced table).
- **Where to look:** gem `ActiveRecordMapper::AssociationIntrospection#resolve_target`, `ActiveRecordMapper::ForeignKeyTargets`. App: the `belongs_to` declaration and `db/schema.rb` `add_foreign_key` lines.
- **Fix:** Set the foreign key in the definition: `chat_message_id { FactoryBakery.bake!(Chat::Message).id }`, or fix the `class_name`.
- **Example (Discourse):** `Chat::MessageSearchData belongs_to :chat_message` names a missing `ChatMessage`, and `chat_message_search_data` has no foreign key constraint, so it keeps `chat_message_id { FactoryBakery.bake!(Chat::Message).id }`.

### unsupported-association-shape

- **Message:** `X#y (has_many) is not supported; assign via an attribute block`
- **Cause:** `association` on a `has_many :through`, `has_one :through` or `has_and_belongs_to_many`.
- **Fix:** Assign it with an attribute block:
  ```ruby
  tags { [FactoryBakery.bake(Tag)] }
  ```

### association-option-errors

All are `ArgumentError` raised when the declaration is evaluated or at bake time. Gem: `associations/dsl.rb`, `associations/declaration_rules.rb`.

| Message | Cause | Fix |
| --- | --- | --- |
| `unknown association option(s) name:; pass attribute overrides as with: {name: "x"}` | An override beside the options | `with: { name: 'x' }` |
| `pass the target class positionally or as factory:, not both` | Both spellings | Keep one |
| `with: must be a Hash of attribute overrides` | `with:` not a Hash | Pass a Hash |
| `persist: must be true or false` | | Use a boolean |
| `a block cannot be combined with persist:; call bake! inside the block` | | Call `bake!` in the block |
| `count: must be a non-negative Integer` | | Use an Integer >= 0 |
| `a block cannot be combined with count:, traits, factory: or with:` | | Use options, or a block |
| `count: is only supported on collections, but Post#user is a belongs_to association` | `count:` on a singular edge | Remove `count:` |
| `persist: is only supported on belongs_to, but Post#comments is a has_many association` | A child cannot be saved before its owner. `Post#comments` names the owner and the edge | Remove `persist:` |

### polymorphic-factory-required

- **Message:** `Note has a polymorphic association :noteable; pass factory: to name its target class`
- **Cause:** An `association :noteable` declaration on a polymorphic edge with no class.
- **Fix:** `association :noteable, Topic`.

### factory-incompatible

- **Message:** `factory: :admin_user is incompatible with Post#editor: expected User or a subclass, got Topic`
- **Cause:** `factory:` resolves to a class that is not the reflection's class or a subclass.
- **Fix:** Name a compatible class or factory.

### no-polymorphic-target-discovered

- **Message:**
  ```
  Note#noteable is a required polymorphic association; no target discovered from: inclusion validator on noteable_type; inverse as: reflections on loaded models; Rails.application.eager_load! (disabled by config). Declare it (e.g. association :noteable, factory: SomeClass) or pass noteable: to name its target
  ```
- **Cause:** A required polymorphic `belongs_to` with no `inclusion` validator on the type column and no loaded `as:` inverse. The last source reads `(disabled by config)` when `eager_load` is false. A database foreign key constraint on the `<name>_id` column narrows candidates to the referenced table (Mastodon's `Doorkeeper::Application#owner` resolves to `User` this way), and supplies its model when no other source found one.
- **Where to look:** gem `ActiveRecordMapper::PolymorphicTargetDiscovery`, `BelongsToBuilder#raise_unresolved!`. App: the owner's validators.
- **Fix:** `association :noteable, Topic` in the definition, or `noteable:` at the call site, or `skip :noteable`. If `eager_load` is off, the `as:` owners may simply be unloaded: enable it, or require the models.
- **Example (Discourse):**
  ```ruby
  FactoryBakery.define(Bookmark) do
    association :bookmarkable, Topic, persist: true   # polymorphic_columns_present needs bookmarkable_id
  end
  FactoryBakery.define(SidebarSectionLink) do
    linkable { Category.find(SiteSetting.uncategorized_category_id) }  # supported linkable type
  end
  ```

### polymorphic-targets-all-failed

- **Message:** `Note#noteable is a required polymorphic association; none of Topic (ActiveRecord::RecordInvalid: ...), Post (...) could be baked. Declare it (e.g. association :noteable, factory: SomeClass) or pass noteable: to name its target`
- **Cause:** Candidates were found but each failed to bake. With a single candidate, the **original** error is raised instead.
- **Fix:** Read each nested error and fix that class's definition, or declare the edge.

### reuse-strategy-errors

All `ArgumentError`. Gem: `associations/declaration_rules.rb`, `associations/reuse_resolver.rb`. `X#y` is the owner model and the edge it declares.

| Message | Fix |
| --- | --- |
| `strategy: :reuse_non_unique is only supported on belongs_to, but X#y is a has_many association` | Remove the explicit strategy from the collection |
| `traits cannot be combined with strategy: :reuse_non_unique on X#y` | Drop the traits or the strategy |
| `strategy: :reuse_non_unique needs a single primary key to pick deterministically, but X has [...]` | Use `:fresh` for composite-key targets |
| `strategy: :reuse_non_unique cannot match encrypted attribute "k" on X` | Do not override an encrypted attribute on a reused edge |
| `strategy: :reuse_non_unique cannot match serialized column "k" on X` | Same for serialized columns |

### cyclic-association

- **Message:** `Node#parent -> Node#parent; declare one side (e.g. parent { nil }) or make it optional`
- **Class:** `FactoryBakery::CyclicAssociationError`
- **Cause:** Auto-building required edges revisits a reflection path: a required self-reference, a mutual required pair, or a declared child block that bakes its own required parent.
- **Where to look:** gem `BelongsToBuilder#ensure_acyclic!`. App: the models' `belongs_to` options and the definitions.
- **Fix:** Declare one side (`parent { nil }`), or `skip :parent`. In a declared collection block, pass the owner: `FactoryBakery.bake(Article, cat: cat)`. `inverse_of` does not help.
- **Examples:**
  - Discourse `UserEmail`: `user { nil }` breaks `User -> primary_email -> UserEmail -> User`.
  - Mastodon `Account`: `skip :moved_to_account` breaks `Account -> moved_to_account -> Account` in `:all`.
  - Mastodon `EmailDomainBlock`: `skip :parent`.
- **Optional edges** never raise this error. They are left `nil`.

---

## Persistence errors

### incomplete-persistence

- **Message:** `bake! did not persist all generated records: Member (assigned to members). Persist the record explicitly via a declaration or override, or change the association's autosave/validate options.`
- **Class:** `FactoryBakery::IncompletePersistenceError`. The bake is rolled back first.
- **Cause:** After the root `save!`, a generated record is still new. Usual reasons: `autosave: false` on the association, `validate: false` on an invalid child, or a parent Rails skipped because it was invalid.
- **Where to look:** gem `PersistenceVerifier`. App: the association's `autosave` / `validate` options, and the named record's own validity.
- **Fix:** Persist the record explicitly in a declaration or override, or fix the association options. Make the named record valid first: `FactoryBakery.bake(Member).valid?`.

### nested-bake-sibling-of-same-class

If `IncompletePersistenceError` names the sibling, the fix is in the current source (0.0.2.0, still Unreleased in CHANGELOG.md; nothing is on rubygems.org). A path: checkout has it; on git:, move `ref:`. Nested `bake!` used to raise `IncompletePersistenceError` when an unsaved sibling shared its class path. It now checks records by build lineage. For example, `association :user, persist: true` on `Invite` saves `user` while a plain `bake` can leave the auto-built `invited_by` unsaved. An enclosing `bake!` verifies the whole invite graph after it saves the invite.

### read-only-target

- **Message:** `Instance is read-only (readonly? is true, e.g. a database view); use FactoryBakery.bake to get a populated record, or create the underlying rows yourself. A persist_with hook is not supported yet.`
  For a required parent the message starts with the chain, for example `InstanceModerationNote#instance -> Instance is read-only (...)`.
- **Class:** `FactoryBakery::ReadOnlyTargetError`
- **Cause:** `bake!` of a model whose `readonly?` is true, or of one that needs a read-only parent that cannot be adopted (empty table).
- **Where to look:** gem `ReadOnlyGuard`. App: `readonly?`, view definitions.
- **Fix:** Use `bake` instead of `bake!` when you do not need a row. Create the rows yourself. For a parent edge: `skip :instance` and set the natural key.
- **Example (Mastodon):**
  ```ruby
  FactoryBakery.define(InstanceModerationNote) do
    skip :instance                  # Instance is a read-only view
    domain { 'example.com' }        # skip also suppresses the natural-key FK column
  end
  ```
- A read-only child under `:all` is discarded, not an error. Mastodon's `User has_many :ips` (a view).

### fk-parent-cannot-be-inserted

- **Message:** `X cannot be inserted: its required Y is invalid (Name can't be blank; ...)`
- **Class:** `FactoryBakery::Error`
- **Cause:** A parent the gem must insert (a raw-FK presence edge) has a required parent of its own that is invalid. Saving it would insert a nil foreign key.
- **Fix:** Make the named grandparent bakeable: a definition for `Y`. The message shows the first three validation messages.

### id-reading-custom-validator

- **Message *(Rails)*:** `Validation failed: ...` or `errors.full_messages` such as `topic mismatch`, `inviter must differ`. A `bake` returns a record that is not `valid?`.
- **Cause:** A custom validator reads a parent's **id**, not the object (`user_id == invited_by_id`, `topic_id == link_topic_id`, `comparison: { other_than: :invited_by_id }`). While parents are unsaved their ids are `nil`, so the comparison is `nil == nil`.
- **Where to look:** App: the validator that mentions `*_id`.
- **Fix:** `association :user, persist: true` on the parent(s) that must have an id.
- **Examples:**
  - Discourse `TopicLink`: `association :topic, persist: true, with: { user: Discourse.system_user }`
  - Discourse `Live::Invite`: `association :user, persist: true`
  - Mastodon `PollVote`:
    ```ruby
    association :poll, persist: true
    association :account, persist: true, strategy: :fresh   # reuse could pick the poll's own author
    ```

### must-exist-error

- **Message *(Rails)*:** `Validation failed: Post must exist` (or `Post can't be blank`)
- **Cause:** A required `belongs_to` is `nil`. Either the associations plugin is not loaded, the mode is `:none`, or the edge is optional in `:required_only` but a custom validator needs it.
- **Fix:** Load the plugin (`config.factory_bakery.associations = { mode: :required_only }`). If a custom validator needs an optional parent, the verified fallback tries to build it after the lean attempt fails. If it still fails, declare `association :post`.

### has-one-created-by-callback

- **Message *(database)*:** `PG::UniqueViolation: duplicate key value violates unique constraint "user_stats_pkey"` or `ActiveRecord::RecordNotUnique`
- **Cause:** An owner callback (`after_create :create_user_stat`) inserts the child, and a child built by the gem or your declaration is autosaved too.
- **Where to look:** App: callbacks on the owner. Gem: `PersistenceAdapter#save_detaching_children!` handles children the gem built itself.
- **Fix:** For a child **you** declared, remove the declaration (let the callback create it), or `skip :user_stat`. For a gem-built child that still collides, report a gem issue naming the callback and the model.
- **Example (Discourse):** `User` with `user_stats` and `user_profile` rows created by callbacks. Fixed in the gem for automatic children (commits `7b65e38`, `63660d8`, `a0a733a`).

### db-only-constraints

- **Messages *(Rails)*:** `ActiveRecord::NotNullViolation`, `ActiveRecord::InvalidForeignKey`, `ActiveRecord::StatementInvalid` with a check-constraint name, `PG::UniqueViolation` for a composite index.
- **Cause:** A rule that lives only in the database: a check constraint, a composite unique index, a trigger, a NOT NULL column with no model validator that the gem filled with a plausible but wrong value.
- **Where to look:** `db/schema.rb` or `structure.sql`.
- **Fix:** A definition line giving the value the database accepts. A `NOT NULL` foreign key is built by the plugin in `:required_only`. Without the plugin it stays `nil`.
- **Note:** A composite unique index forces a fresh parent on that edge under `:reuse_non_unique`, and its values are not regenerated on collision.

---

## Value generation errors

### unique-value-collisions

- **Message:** `could not generate a unique value for User#email: "x" keeps colliding after 10 attempts. Constraints: <validator descriptions>. Pass an explicit value with an override or relax the constraint.`
- **Class:** `FactoryBakery::Error`
- **Cause:** The value space of a uniqueness-validated column is exhausted: a single-value `inclusion` list plus uniqueness, an enum, a tiny `length`, or a `format` that allows few values.
- **Where to look:** gem `UniquenessEnforcer`. App: the validators and the definition for that column.
- **Fix:** Override with a generator, or widen the rule. Regeneration applies only to values the gem generated: after two collisions it appends an entropy suffix unless the column has a `format`, `inclusion`, `enum`, numericality rule, exact length, or a cap with no room.
- **Literals:** a value a definition or an override sets literally is not regenerated. Two bakes that collide with each other usually mean a literal was set. See [literal-override-uniqueness](#literal-override-uniqueness).
- **Example (Mastodon):** `Account#username`: two mutually constraining format regexes. A declared value wins: `username { "fb_#{SecureRandom.hex(5)}" }` (unseeded: pin a literal while replaying a failure; prefer a file-level counter, which repeats with the seed only when its evaluation sequence repeats).

### format-exhaustion

- **Message:** `could not generate a format-compliant value for User#code (with: /\A...\z/; length constraints: {...}): "x" failed after 10 attempts. Pass an explicit value with an override or relax the constraints.` For a text column cast to JSON the first words read `could not generate a JSON value for`.
- **Cause:** The regex cannot be satisfied (`/\Afoo(?=bar)\z/`), exceeds the generator's bounds (256 characters, depth), uses a construct `regexp_parser` cannot parse, or clashes with a `length` rule or a second regex.
- **Where to look:** gem `AttributeFillers::StringFiller`, `RegexGeneration`. App: the `format:` options.
- **Fix:** Give the value: a definition line or an override.
- **Example (Mastodon):** `Account#username` (two regexes). Discourse `Group#name`: `name { "smoke_group_#{SecureRandom.hex(4)}" }` (unseeded: pin a literal while replaying a failure; prefer a file-level counter, which repeats with the seed only when its evaluation sequence repeats).

### numeric-constraint-exhaustion

- **Message:** `could not generate a value satisfying the numeric constraints for X#age (other_than: 3, even: true): 7 violates the constraints. Pass an explicit value with an override or relax them.` (Also appears for `parity within a..b`.)
- **Cause:** Bounds, `other_than`, exclusion and parity rules leave no value.
- **Fix:** Provide a value.

### exclusion-exhaustion

- **Message:** `could not generate a value for X#name that satisfies exclusion after 10 attempts: ["a", "b"]. Pass an explicit value with an override or relax the constraint.`
- **Cause:** Array or JSON filler could not avoid the forbidden values.
- **Fix:** Provide a value.

### length-resolution-error

- **Message:** `X#name: length :maximum <raw> resolved to <value>, which is not a usable length; pass an explicit value with an override or use a non-negative Integer`
- **Cause:** A lazy length option (Proc or Symbol) returned something that is not a non-negative Integer.
- **Fix:** Fix the option, or pass the value.

### length-option-raised

- **Message:** `X#name: length :maximum <option> raised NameError: ...; define referenced constants before baking or use a literal integer`
- **Cause:** A lazy length option referenced a constant that is not loaded yet when baking started.
- **Fix:** Load the constant before baking, or use a literal.

### inclusion-proc-raised

- **Message:** `X#status: inclusion :in proc raised NameError: ...; define referenced constants before baking or use a literal array/range`
- **Cause:** A Proc `in:` option referenced a constant that is not defined at bake time.
- **Fix:** Ensure the constant is loaded, or use a literal.

---

## Construction, attachments, mappers

### construction-failed

- **Message:** the model's own error with ` (FactoryBakery also tried unscoped and callback-free construction)` appended.
- **Cause:** `new` raises, and neither `unscoped { new }` nor callback-free construction rescued it (a raising `default_scope` combined with `after_initialize`, or Rails internals that differ).
- **Where to look:** gem `ActiveRecordMapper::Construction`. App: `default_scope`, `after_initialize`.
- **Fix:** Fix the model's initialization, or construct with `initialize_with` values the constructor accepts.

### attachment-fixture-missing

- **Message:** `no bundled attachment fixture matches ["application/zip"]; declare the attachment explicitly or allow one of image/png, image/jpeg, image/gif, image/webp, video/mp4, audio/mpeg, application/pdf, text/plain`
- **Cause:** The attachment's content-type rule excludes every bundled fixture.
- **Fix:** Declare the attachment in a definition, or allow one of the listed types.

### sequel-gem-missing

- **Message:** starts `factory_bakery/sequel requires the sequel gem, but it is not available.`
- **Fix:** Add `gem 'sequel'` to the Gemfile and bundle.

### sequel-associations-unsupported

- **Message:** `no associations on Book; it is not ActiveRecord`
- **Cause:** `association :x` on a Sequel model. The plugin does not build Sequel associations.
- **Fix:** `author { FactoryBakery.bake!(Author) }` in an attribute block.

---

## Domain rules inference cannot know

These produce a record that is not `valid?`, or a rule error from `bake!`. Fix with one definition line, and say that the rule is app-specific.

### registry-and-inclusion-lists

- **Symptom:** `Validation failed: Source is not included` or a custom message. The valid values come from an app registry, a provider list or site settings.
- **Fix:** Return a value from the registry in a block.
- **Examples:**
  - Discourse `AdminDashboardReport`: `source { 'core_report' }`
  - Discourse `McpGroupScope`: `scope { DiscourseMcp.registry.scopes.first }`
  - Discourse `DiscourseChatIntegration::Channel`: `provider { 'discord' }`
  - Mastodon `Webhook`: `events { ['status.created'] }`
  - Mastodon `Follow`: `languages { [] }` (the language validator rejects random words)
  - Discourse `LlmModel`: `provider { LlmModel::OPEN_AI_PROVIDER_NAME }`
- A readable `inclusion:` validator (`in:` an array, a range or a Proc on the model) is handled, and so are enums. A **registry** that only custom validation code consults (a `validate` method, a custom validator, a site setting) is invisible to the gem: declare a value from it.
- When a custom validator rejects the drawn enum value, boolean or STI type, the gem does not try the others: which one to use is a domain decision ([ADR-0008](adr/0008-user-chooses-domain-values.md)). Pin it in the definition.

### random-value-rejected-by-app-rule

- **Symptom:** The same model is valid on some runs and invalid on others. The failure text starts its explanation with `FactoryBakery could not produce a valid X. Invalid attributes:` — the errors, then the seed line (`Seed N from <source>. Reproduce: <command>`), then `Chosen at random: provider = "bedrock"` (or another value), then a `pin it in <file>` line, then a `FactoryBakery.define(...)` snippet, then an `Agent:` line. `bake!` raises the usual error class (for example `ActiveRecord::RecordInvalid`) with that text appended after the original message.
- **Cause:** A validator the gem cannot read (a custom `validate` block, or a rule that depends on another attribute or setting) rejects the value FactoryBakery drew at random. FactoryBakery does not retry: the seed reproduces the same value every run.
- **Fix:** Pin the value in your definitions file, using a value your validations accept. The snippet's `{ nil }` is a placeholder: replace it. Re-run with the same seed to confirm: `FACTORY_BAKERY_SEED=1234` (or the `rspec --seed` / `bin/rails test --seed` command the message prints). The value the message shows is what was drawn, not a fix.

  ```ruby
  FactoryBakery.define(LlmModel) do
    provider { 'open_ai' } # was randomly "bedrock"; use a value your validations accept
  end
  ```
- **Where to look:** `FactoryBakery.explain(record)` prints the same text for a record from plain `bake` after `valid?`. `bin/rails factory_bakery:doctor` prints it under each failing model.
- **Smallest fix:** A definition line. An override at the call site is the same fix for one test.

### time-relative-validations

- **Symptom:** A validator compares a time or date to "now" in custom code: `expires_at` must be within 5 minutes to 1 month, a future effective date.
- **Fix:** A block computing a value relative to now: `expires_at { 1.day.from_now }`.
- **Example (Mastodon):** `Poll`: `expires_at { 1.day.from_now }`; `TermsOfService`: `effective_date { Date.current + SecureRandom.random_number(1..300) }` (unseeded: pin a literal while replaying a failure; prefer a file-level counter, which repeats with the seed only when its evaluation sequence repeats).
- `comparison:` and `numericality:` bounds, including Proc and Symbol bounds, are handled without a definition.

### structured-text-columns

- **Symptom:** `invalid input syntax for type json`, or a validator that parses a text column as JSON, YAML or a custom format.
- **Cause:** The column is plain text. The gem generates a JSON object string only when an expression index casts the column to JSON. A validator that wants a specific shape is invisible to it.
- **Fix:** A block returning the shape.
- **Examples:**
  - Discourse `FormTemplate`: `template { [{ "id" => "fb_field", "type" => "input", "label" => "Smoke" }].to_yaml }`
  - Discourse `DiscourseChatIntegration::Channel`: `data { { 'name' => ..., 'webhook_url' => ... } }`
  - Discourse `ThemeSettingsMigration`: `diff { { additions: [], deletions: [] }.to_json }`

### side-effecting-writers

- **Symptom:** A network call, a job, or a file write happens while baking.
- **Cause:** A setter with side effects received a value. The gem never hands `*_remote_url`-style writers a generated value, but other setters (for example one that fetches a URL) are filled when required.
- **Fix:** `skip :setter_name`, or a definition returning a safe value.
- **Example (Mastodon):** `AccountAlias`: use a local account so no WebFinger request is made. `Account#avatar_remote_url` needs nothing: see [#remote-url-left-blank](#remote-url-left-blank).

### remote-url-left-blank

- **Message (WARN log, once per model and attribute per process):** `left Account#avatar_remote_url blank on purpose: assigning it downloads the URL. Set it in a definition or pass it as an override to fill it.`
- **Cause:** The attribute matches the guarded-writer pattern — `remote_url`, `*_remote_url` and `remote_*url` (Mastodon's `Remotable`, Paperclip-style URL fetchers). Assigning it downloads the URL: left alone, the Active Record/Active Model mapper never hands it a generated value; on a NOT NULL column without a default it writes `''` through the writer. Undeclared guarded writers warn once per model and attribute when the result is blank; a nonblank default survives without a warning. The WARN is not proof of success: it records a skipped inferred assignment; check the returned record or the exception for the result — a presence validation on the omitted attribute still fails `bake!`.
- **Where to look:** gem `ActiveRecordMapper::ConstraintReader::REMOTE_URL_WRITER_PATTERN`, `AttributeFillers::GuardedWriterFiller`, `RemoteUrlNotice`.
- **Fix:** Nothing, when blank is fine. To fill it, set it in a definition or pass it as an override (stub the HTTP call in the test). A definition or override also silences the warning. `skip` drops the empty-string assignment and suppresses the warning; on a NOT NULL column without a default a skipped writer ends in `NotNullViolation` unless a presence validation raises `RecordInvalid` first.

### derived-values-need-the-source

- **Symptom:** `Validation failed: Slug has already been taken` on the second bake.
- **Cause:** A value derived from another (a slug from a title) collides because the source column is optional and left `nil`, so every derived value is `''`.
- **Fix:** Fill the source: `bake(Post, fill_optional: [:title])`, or a definition line for it.

---

## Interaction with other things

### reuse-picks-owners-own-parent

- **Symptom:** `Validation failed: ... has already been taken`, or a rule such as "voting on your own poll" fails, only with `strategy: :reuse_non_unique`, and only sometimes.
- **Cause:** The strategy reuses the oldest matching row. A custom validator (invisible to the gem) forbids that row for this owner.
- **Fix:** `strategy: :fresh` on that edge: `association :account, persist: true, strategy: :fresh`.
- **Example (Mastodon):** `PollVote`.
- **Note:** Unique **indexes** and uniqueness **validators** on the foreign key are seen: those edges build fresh automatically.

### literal-override-uniqueness

- **Symptom:** `Validation failed: Items is invalid` (the owner), or a child's `has already been taken`.
- **Cause:** `association :items, count: 2, with: { label: 'same' }` gives every child the same literal. FactoryBakery does not make literals unique.
- **Fix:** Leave the value to inference, or build the collection in a block with distinct values:
  ```ruby
  association(:items) { |cat| Array.new(2) { |i| FactoryBakery.bake(Item, cat: cat, label: "item-#{i}") } }
  ```

### all-mode-invalid-optional-child

- **Symptom:** Under `:all`, an owner is invalid because an auto-built child or parent is invalid, or a cycle appears.
- **Cause:** `:all` builds optional edges. An optional edge that fails is dropped, but a model validator that validates the **collection** (Discourse `LlmModel` with vision dependents, `Theme` with parent relations) can reject a plausible child.
- **Fix:** `skip :vision_dependents, :parent_theme_relation` in the owner's definition. Prefer `:required_only` unless a test needs the optional graph.

### declaration-blocks-run-twice

- **Symptom:** A counter, a log line, an HTTP stub or a setting changes twice per bake.
- **Cause:** The verified fallback discarded the lean attempt and rebuilt. Database writes are rolled back, other side effects are not.
- **Fix:** Make the block idempotent, or guard it. Give the model's custom validation what it needs in the definition so the lean attempt is valid.

### subclass-uses-parent-definition

- **Symptom:** A subclass bakes with values from its parent's definition, and a stricter validation on the subclass rejects them (common with STI).
- **Cause:** A class with no definition of its own uses the nearest ancestor class's definition, traits included. `Object` and `BasicObject` are never inherited from, and modules and symbol factories are not searched.
- **Fix:** Give the subclass its own definition. An exact definition always wins over an inherited one and **replaces** it (definitions do not merge), so repeat the parent's lines and traits the subclass still needs. When the parent's definition already bakes the subclass, write none.
- **Example (Discourse):** `Chat::NullUser < User` needs no definition: it uses `User`'s.

### stale-class-definitions

- **Symptom:** After a code reload, `bake(User)` ignores the definition.
- **Cause:** A class-keyed definition points at the class object that existed when the file loaded.
- **Fix:** Reload definitions (`FactoryBakery.find_definitions`), or use a symbol factory with `klass:`-free resolution. Tests normally do not reload.

### definition-load-errors

- **Symptom:** A `NoMethodError`, `NameError` or duplicate-definition error at boot from a definition file.
- **Cause:** FactoryBakery and factory_bot both load `spec/factories`, so one evaluates the other's files. A class-keyed stub naming a missing model (a `factory_bakery:definition` generated for a class that does not exist, e.g. `Admin::Post`) raises `NameError` when the file loads. A syntax or constant error inside a file propagates, and files from earlier paths are already loaded.
- **Fix:** Put FactoryBakery definitions in `spec/bakery` and set `config.definition_paths` inside the generated initializer's `tap` block. Fix or delete the stub's name. See [Migrating](guide/migrating-from-factory-bot.md#step-2-set-up-side-by-side).

---

## Factory attribute errors

| Message | Cause | Fix |
| --- | --- | --- |
| `Static attributes are unsupported; use name { "Ada" }` | A value was passed to the declaration as an argument (`name 'Ada'`) | Use a value block such as `name { 'Ada' }`, or `skip :name` to omit it |
| `Cyclic attribute dependency: a -> b -> a` | The displayed chain of sibling reads returns to an attribute already being resolved | Change one declaration to break the cycle, or pass a call-site value for one attribute in the chain |
| `Use name { ... } to declare a value, or skip :name` | An attribute declared with neither a block nor an argument. This includes a trait body that calls another trait by bare name (`admin`): a trait cannot call a trait | Give it a block, or `skip :name`. For a trait call, repeat the lines or pass both traits at the call site |
| `Use add_attribute(:skip) { ... } to declare a value` | `add_attribute` called without a block | Pass the value block |

## Silent failures

These raise nothing. The result is wrong. Look here when a value is missing or odd.

### silent-failures

| Symptom | Cause | Fix |
| --- | --- | --- |
| A typo in an attribute name does nothing | Values are assigned through setters. A missing setter is skipped | Fix the name |
| A plugin DSL method does nothing | The plugin is unregistered (or never loaded). Only `association` raises | Register the plugin |
| An optional column is `nil` | Expected. Only required attributes are filled | `fill_optional:` or a definition line |
| `bake` returns an invalid record | Overrides are not validated, and it only probes when needed | Call `valid?` |
| A sequel `many_to_one` is `nil` | Sequel associations are never built | Assign in a block |
| A `has_many_attached` is empty | Not filled | Declare it |
| `bake` inserted a row | A raw-FK presence parent, `persist: true`, or your own `bake!` in a block | Expected |
| STI `type` is `nil` on the base | Left to Rails | Bake the subclass, or `initialize_with(type: 'Sub')` |
| Abstract STI base fails validation | Concrete subclass choice is not discoverable | `initialize_with(type: 'CategoryChannel')` (Discourse `Chat::Channel`) |

### null-objects-and-unbakeable-classes

- **Symptom:** A class that is never saved (a null object, a placeholder) fails `bake!`, or `doctor` lists it.
- **Fix:** Name the other models (`factory_bakery:doctor[A,B]`), or accept its failing line. These are not bakeable by design (Discourse's `Chat::NullMessage`).

---

## When to file a gem issue

File one when **all** hold:

1. The failing rule is a declared validator or column constraint (a discoverable constraint), not app logic.
2. A minimal model reproduces it with `FactoryBakery.bake(Model)` alone.
3. A definition line would work around it, but inference should have produced the value.

Include the gem version (`FactoryBakery::VERSION`), the model, the validator, the exact message and the repro. Issues live at `mohammed-io/factory_bakery` (GitHub). Use the `needs-triage` label.
