## [Unreleased]

### Association fixes

- A read-only parent on a raw-FK presence edge (a model whose `readonly?` is true, e.g. a database view) is never saved: the plugin adopts an existing row of exactly that class so the FK points at a real record, and inserts nothing into the read-only table. When the view has no row, `bake` returns the child with the unsaved parent and `bake!` raises `ReadOnlyTargetError` instead of letting a raw `ActiveRecord::ReadOnlyRecord` escape. The generated-record registry follows the adopted row, so `bake!`'s persistence check and read-only guard inspect the object actually assigned to the owner; a read-only record that is already persisted is left alone because `bake!` never writes it.
- Under `bake!` a read-only `belongs_to` parent is never autosaved on any edge, not only on raw-FK presence ones: an association-presence edge (`belongs_to :x, optional: false`) now adopts an existing row of the read-only class so the root `save!` does not write it, and an empty table fails the bake with `ReadOnlyTargetError` instead of `ActiveRecord::ReadOnlyRecord`. Plain `bake` still returns the populated, unsaved parent with no database read.
- A `strategy: :reuse` miss on a raw-FK presence edge under plain `bake` now falls back to the ordinary fresh build and insert — the same documented exception to the unsaved graph `:fresh` makes — instead of raising `FactoryBakery::Error`. The `TargetBuilder` and auto-builder paths now assign whatever `FkParentPersistence.settle` returns, and the README's strategy and read-only sections describe both behaviors.

### Review fixes

- Fixed small `in:` integer ranges producing only even values (and raising for `in: 3..3`): with no parity rule every integer now matches.
- `if:` / `unless:` Symbol conditions are now called with `send`, as Rails does, so private predicates work; one-argument Proc conditions run against the record.
- `FactoryBakery.fill_optional =` is validated and normalized like the per-call option (`%i[bio]` works; `'true'` raises).
- Metadata columns that mention a body word (`content_type`, `message_id`, `text_size`, …) no longer receive paragraph values.
- A polymorphic candidate that fails after generating records is rolled back and trimmed, so `bake!` no longer raises `IncompletePersistenceError` for its leftovers; a required natural-key edge with a nullable key column now generates the key; empty polymorphic discovery results are no longer cached, the cache key includes the eager-load flag, a failed eager load is retried, and the cache is cleared on Rails reload (`config.to_prepare`).
- A presence-validated file attachment no longer leaks into the ActiveRecord attribute universe when the attachments plugin is not loaded (no more `NoMethodError` on a plugin-less `bake`). The attachments plugin reads presence and content-type rules only through its adapters, and resolves `if:` / `unless:` through the mapper's `Conditional` instead of a second copy.
- Nullable columns carrying `uniqueness` or `comparison` are now filled on the default path: Rails treats a NULL duplicate as taken and a nil comparison as invalid. Model `validate` overrides and Sequel `validation_helpers` now count as unreadable validation, so the verified fallback runs for them (a mapper that cannot answer gets the conservative "verify" default).
- A plain `has_many` no longer makes a model look custom: Rails' autosave `validate_associated_records_for_*` callbacks are ignored by `custom_validation?`, so ordinary bakes really do skip `valid?` unless a defaulted validated column was left unset or app validation is unreadable.
- Each verified-fallback attempt now runs in its own savepoint. The lean attempt's writes (declaration-block `bake!` calls, FK-presence parents) roll back before the rebuild, and `:reuse` cache entries pointing at the discarded graph are dropped. Declaration blocks may run twice when the fallback fires.
- Validator conditions are evaluated once per (record, validator, attribute) between assignment phases instead of up to six times per bake, with results scoped to the current bake/fiber and invalidated when setters change the record. Added `spec/factory_bakery/required_only_review_spec.rb` and default-path uniqueness coverage; see [ADR-0006](docs/adr/0006-required-only-baking-and-verified-fallback.md).

### Semantic string candidates (issue #59)

- Name-derived strings now use a most-specific-first semantic rule table: `title` / `subject` / `headline` get a 4–8-word sentence (>= 20 chars) instead of a single word; `body` / `raw` / `content` / `description` / `message` / `text` get a multi-sentence paragraph (>= 60 chars); `filename` / `file_name` get `<word>.png`; `host` / `hostname` / `domain` get `<word>.example.com`; `ip` / `ip_address` get a TEST-NET-1 address; and `timezone` / `time_zone` get `UTC` or a real IANA zone. Snake-case boundaries keep `description` out of the `ip` rule and `hostname` / `file_name` out of the generic `name` rule. Email, identifier-like names, phone, address, priority, slug and label keep their existing shapes.
- Title sentences keep the issue #58 entropy suffix: it is appended after the sentence, and an explicit length cap truncates the base rather than the six digits. The #58 value-shape spec was updated to the new title shape; titles still pass a "min 15 chars, at least 3 distinct words" validator.
- `url` / `*_url` / `website` / `endpoint` / `uri` / `link` now generate an `https://` URL on a reserved domain (RFC 2606 `example.com`, `example.test`, `sub.example`) rather than a real-looking host. Every generated host, URL and IP is a reserved test value (RFC 5737 for IPs); no network is used.
- A URL-named attribute with a declared `format` first offers a few plausible reserved-domain URL candidates to StringFiller's verifier, which checks them against the regex, length and exclusion constraints; when none fits, generation falls back to `RegexGeneration`. Both the Discourse WebHook lookahead regex and `URI.regexp(%w[http https])` already baked valid via `RegexGeneration` (#65) — the candidate-first step keeps their values reserved URLs instead of synthesized characters. It lives in `PlausibleStrings` / `StringFiller`, never in the isolated generator.
- `inet`, `cidr` and `tsvector` columns are routed to the string filler from the mapper's normalized column type in `ConstraintSet` (ADR-0001): `inet` → `192.0.2.<n>`, `cidr` → `192.0.2.0/24`, `tsvector` with a presence requirement → lorem words. The ActiveRecord mapper normalizes a text-castable type with no registered cast type (its `type` is nil, but its `sql_type` is `tsvector`) into a plain symbol; no framework class is read in the core.
- Added `spec/factory_bakery/semantic_candidates_spec.rb` covering every row through `FactoryBakery.bake`, including the lookahead format, the min-15/3-word title validator, reserved-value assertions, the synthesis fallback, and PG-only `inet` / `cidr` / `tsvector` examples guarded like the other PostgreSQL specs.

### File attachments plugin (issue #62)

- Added the opt-in attachments plugin (`require 'factory_bakery/attachments'`). A file attachment a valid record needs — one whose presence validator applies, `if:` / `unless:` included — is filled with a tiny real fixture bundled inside the gem, picked from the content types the attachment allows: a 1x1 PNG by default, then JPEG, GIF, WebP, MP4, MP3, PDF and plain text. `type/*` wildcard and Regexp rules are understood, and an attachment whose rules no fixture satisfies raises a clear `FactoryBakery::Error` naming the allowed types.
- Active Storage (`has_one_attached`) and Paperclip / kt-paperclip (`has_attached_file`) are supported; `has_many_attached` is left alone. `bake` stays database-free and never touches the network, while `bake!` persists the blob and the attachment row inside the existing savepoint and uploads the file on commit. Optional attachments stay empty unless `fill_optional: true` (or a list naming them) asks for them, and declarations, call-site overrides and `skip` suppress the plugin just like any other attribute.
- The fixtures ship under `lib/factory_bakery/attachments/fixtures/` (about 3 KB total) and are listed explicitly in the gem's `files`. Paperclip support is covered against a minimal stand-in module; real-gem coverage is pending (the gem is not in the bundle).

### Polymorphic target discovery (issue #60)

- A required polymorphic `belongs_to` is no longer auto-declaration-only: the ActiveRecord mapper discovers candidate target classes from an `inclusion:` validator on the `*_type` column, then from `has_many`/`has_one ..., as:` inverse reflections on loaded models (matching a declared `class_name` against the baked class or its STI ancestors/descendants). When both are empty and Rails is present, one `Rails.application.eager_load!` per process is attempted before a second inverse scan. All framework reads stay in the mapper per ADR-0001; the plugin consumes only ordered candidate classes and source names.
- Candidates are ordered deterministically (non-abstract, existing table, then class name) and the first that bakes cleanly wins; `strategy: :reuse` reuses an existing row of a candidate first. The result is cached per (class, association) for the process. When nothing is discoverable, the original actionable error remains and now lists the sources tried.
- Added `Associations.eager_load` (default `true`, also accepted in `config.factory_bakery.associations` and `Associations.with`) to gate the eager-load step for test environments; it costs a full model load on first use. Explicit `association … factory:`, call-site overrides and `skip` still suppress auto-build entirely.
- Added `spec/factory_bakery/associations/polymorphic_discovery_spec.rb` covering inclusion-validator and inverse/STI discovery, deterministic choice, no-candidate errors, precedence, reuse and the observable descendants-scan cache. README documents discovery and the new setting.

### Name-like value entropy (issue #58)

- Heuristically generated values for name-, title-, slug-, key- and label-like attributes now end in a six-digit random suffix (`"Voluptas 482193"`, `"voluptas-482193"`), so values an app derives from them (Discourse's `Category#slug` from `name`, normalized keys) stay distinct across bakes even though the derivation is invisible to validator-based uniqueness. Emails, identifier-like names (`username`, `login`, `handle`, `nickname`, `screen_name`), declared formats and declared or overridden values keep their existing shapes.
- Length limits are respected by truncating the base and keeping the suffix; when only the digits fit, the value is the digits alone. The suffix uses the global RNG, so `srand` keeps a seeded run deterministic.
- The Sequel unique-index spec now simulates collisions on a non-derived column.

### Validated virtual attributes on ActiveRecord models (issue #57)

- ActiveRecord models now also get attributes that are validated but are not columns filled when they expose a public setter: a `has_secure_password` `password` (and its `password_confirmation`), an `attr_accessor` with presence, an acceptance flag such as `terms_of_service`, and confirmation twins. The attribute universe is columns plus validator-declared names, so a bake of a Devise/password-style model no longer fails with "Password can't be blank" while every column is filled.
- These attributes follow the required-only rule: they are filled when an applicable validator rejects `nil` (honouring `allow_nil` / `allow_blank` and `if:` / `unless:` for the record being baked). Acceptance and confirmation attributes are filled too, because both tolerate `nil` by default yet only mean something with a value — this is what makes has_secure_password's confirmation-only validators produce a password. Confirmation twins keep using the existing confirmation filler, so they match both generated and overridden source values.
- Association names, column aliases and guard columns (foreign keys, polymorphic type, STI discriminator, primary key, counter caches) are never added, and a validated virtual attribute without a setter is ignored without error.

### Read-only targets (issue #55)

- A record whose `readonly?` is true (a database view, or any model that marks instances read-only) is now a first-class `bake` target: attributes and required associations are filled as usual, and the unsaved record is `valid?` when the discoverable constraints allow it. Read-only detection reads the instance through the mapper's persistence adapter, so instance-level read-only records are covered too.
- `bake!` now raises `FactoryBakery::ReadOnlyTargetError` (a `FactoryBakery::Error`) before attempting a save instead of letting the write fail obscurely. The error names the model and suggests `bake` or creating the underlying rows; a `persist_with` hook is noted as a future option. When the read-only record is a required parent, the error names the association chain (for example `InstanceModerationNote#instance -> Instance is read-only`).
- The check runs after graph building but before the root save, inside the existing savepoint: any parent row inserted earlier by the graph is rolled back, leaving the database unchanged. Non-transactional targets are checked before their `save!` too. Added `spec/factory_bakery/read_only_spec.rb` covering populated/valid `bake`, the clear `bake!` error with row-count assertions, instance-level detection, FK-parent rollback, and natural-key and id-keyed parent chains. README documents the behavior.

### Models whose `new` raises (issue #56)

- Baking no longer gives up when a model cannot be instantiated with `new`. Construction retries, only after the previous attempt raised: `klass.new(...)` first, then `klass.unscoped { klass.new(...) }` (fixes models whose `default_scope` raises while Rails applies its create attributes, and keeps `after_initialize` defaults), then callback-free construction (allocate, restore the default attributes and run the framework's internal setup without the initialize callbacks; fixes models whose `after_initialize` raises). The order matters because the last step drops app-defined initialization.
- Callback-free construction depends on framework internals, so it is guarded by a capability check: on a version that does not provide them the step is skipped and the original error is re-raised. The fallbacks live in the ActiveRecord mapper, reached through the new `MapperRegistry.construct` seam, so the framework-agnostic core stays framework-free and plain objects keep the ordinary constructor.
- `initialize_with` values, declarations, overrides and heuristics are applied exactly as for an ordinary bake; when a fallback had to skip the constructor, `initialize_with` values are applied through setters. A normal model still calls `new` exactly once. When every strategy fails, the original exception class and message are re-raised with a note that fallbacks were tried.
- `bake!` saves these records normally (saving does not run `after_initialize`). Uniqueness probing works for both cases: Rails' own uniqueness validator already queries `unscoped`, and a record that cannot be `dup`ed because its `after_initialize` raises is probed through a callback-free copy instead.

### Natural-key `belongs_to` (issue #54)

- A `belongs_to` keyed on a natural key (`foreign_key: :domain, primary_key: :domain`) no longer treats its NOT NULL column as a reason to build the parent. With `optional: true` (or `belongs_to_required_by_default` false) the key column is filled like any other string and the association is left alone, so baking a model that points at a read-only view no longer tries to insert that view. Id-keyed edges keep the existing NOT NULL rule.
- The FK column of a natural-key edge is no longer a guard column: heuristics fill it, and a call-site or declared value is kept. When the edge is required, the auto-built parent receives that value as its key override, so the parent's key, the child's FK and all parents sharing the column agree.
- Natural-key parents are built after instantiation rather than in the heuristic layer, so FK overrides propagate to them while an explicit association assignment, `skip` or declaration still suppresses the build. `:all` builds them too; `:none` does not.
- Added `spec/factory_bakery/associations/natural_key_spec.rb` covering optional and required edges, three parents on one key, FK overrides, `bake!` persistence, mode boundaries and the unchanged id-keyed rule. README documents the behaviour.

### Enums declared on `alias_attribute` (issue #61)

- Changed constraint discovery so an enum registered under an `alias_attribute` name is found when the aliased column is filled (`alias_attribute :kind, :kind_code` + `enum :kind, ...`). Column and alias resolve to the same schema facts and enum values in both directions, and the pair forms one alias group so it is filled and decided once.
- Fixed `ArgumentError` (`'45' is not a valid type`) when baking Discourse-style models whose enum lives on an alias: the aliased column now receives a valid enum label instead of a random integer, and `bake!` persists it.
- The STI discriminator guard now applies only to a real inheritance column, so `alias_attribute :type, :other_column` leaves `other_column` fillable while models with an actual `type` column stay guarded.

### Required has_one auto-build (issue #53)

- In `:required_only`, a direct `has_one` with a presence validator that applies to the owner is now built automatically. `if:` / `unless:` conditions are evaluated on the populated owner through the ActiveRecord mapper's condition-aware rule, so a guarded requirement (`unless: :skip_email_validation`) is honoured.
- The child is baked through the associations plugin's existing `TargetBuilder`, so the association's create scope (including `where(primary: true)`), foreign key and verified inverse apply before the child's heuristics. For a scoped `has_one` where Rails cannot infer the inverse, it is derived from the matching `belongs_to`, preventing a second owner build and `CyclicAssociationError`.
- Explicit declarations, call-site assignments and `skip :name` suppress the auto-build; `has_one :through` is never built. `bake!` persists the child with its owner in the same transaction and rolls both back on failure.
- Added `spec/factory_bakery/associations/required_has_one_spec.rb` covering scoped builds, back-references, conditional guards, no-validator and `:none` cases, precedence, and persistence/rollback. README documents the behaviour.

### Attribute omission (issue #52)

- Added `skip :attribute` to definitions and traits. An omitted attribute is left at the model's current value/default and its setter is never called. `skip` accepts several names and participates in normal declaration precedence: a later declaration or trait replaces an omission, a later `skip` replaces a declaration, and a call-site override (including explicit `nil`) wins and calls the setter.
- An omission covers the whole alias group, so `skip :account` suppresses the association, its foreign keys and polymorphic type column alike, along with heuristics and plugin auto-build for that group.
- Added `add_attribute(:skip) { ... }` for declaring a real attribute named `skip`; `skip` with a value block now raises a clear error instead of silently dropping the declaration. README documents the DSL and CHANGELOG records the change.
- Added `spec/factory_bakery/attribute_omission_spec.rb` covering defaults and never-called setters, trait and call-site precedence, belongs_to/polymorphic alias groups, and the reserved-name escape hatch.

### Required-only baking (BEHAVIOUR CHANGE, issue #51)

- **Behaviour change:** a default bake now fills only the attributes a valid record needs. Non-column-backed attributes, `NOT NULL` columns without a default, blank defaults with an applicable presence validator, and nullable columns with an applicable nil-rejecting validator (`presence`, `inclusion`, `format`, `numericality`, `acceptance`, `uniqueness`, `comparison`, `length` with `minimum > 0`, all respecting `allow_nil` / `allow_blank`) are still generated. Every other column keeps its database default or stays `nil`, and its setter is never called. Conditions are resolved for the record being baked, so an `if:` / `unless:` guard is honoured when deciding whether a column is needed. Custom `EachValidator`s do not force a fill.
- Added a verified fallback: when leaving optional columns unset makes a record invalid — for example app-specific validation needs one of two optional columns — the builder rebuilds once with optional columns filled and returns that result. The required-only result is preferred when valid, the fallback runs at most once for nested parents, and it is skipped when the caller already supplied every optional column. Verification is limited to cases where heuristics cannot guarantee validity (a defaulted validated column left unset, or validation logic that is not discoverable as constraints such as a custom validator or a `validate` override); framework-owned autosave callbacks on `has_many` do not qualify, so an otherwise plain model keeps skipping `valid?`.
- Added the `fill_optional` opt-in to restore the old "fill every column" behaviour: `FactoryBakery.configure { |c| c.fill_optional = true }` / `FactoryBakery.fill_optional = true` globally, or `bake(Model, fill_optional: true)`, `bake(Model, fill_optional: false)` and `bake(Model, fill_optional: %i[bio website])` per call. Per-call settings also apply to nested bakes. README documents the rule and the opt-in.
- Added `spec/factory_bakery/required_attributes_spec.rb` covering the rule, the opt-in (global, per-call, list and opt-out), the never-called setter, and the verified fallback including nested parents.

Specs deliberately switched to the `fill_optional: true` opt-in (or updated to the new rule) because they asserted that optional columns get filled:

- `spec/factory_bakery/bake_spec.rb` — full-column bake, confirmation, acceptance, enum, and defaulted-column examples.
- `spec/factory_bakery/attribute_fillers/json_filler_spec.rb` — all json/jsonb bake and bake! examples, exclusion, uniqueness and other-column-type routing.
- `spec/factory_bakery/attribute_fillers/array_filler_spec.rb` — non-PostgreSQL array-ish column example.
- `spec/factory_bakery/identifier_shaped_strings_spec.rb` — unconstrained identifier-shaped values and ordering against the generic name rule.
- `spec/factory_bakery/belongs_to_columns_spec.rb` — non-FK integer column and composite-FK name examples.
- `spec/factory_bakery/comparison_options_spec.rb` — symbol/proc bounds, cross-attribute bounds, cyclic bounds, `:in` and literal bound examples (all bake calls).
- `spec/factory_bakery/counter_cache_spec.rb` — non-counter columns, plain `_count` column and has_many-through examples.
- `spec/factory_bakery/database_constraints_spec.rb` — JSON column round-trip example.
- `spec/factory_bakery/defaulted_value_validators_spec.rb` — defaulted + uniqueness example.
- `spec/factory_bakery/length_option_forms_spec.rb` — proc/symbol bound and resolution-failure examples (all bake calls).
- `spec/factory_bakery/numeric_constraint_hygiene_spec.rb` — `other_than` on float, date and datetime examples.
- `spec/factory_bakery/presence_spec.rb` — non-blank default with `presence: true` example.
- `spec/factory_bakery/proc_inclusion_spec.rb` — exclusion proc evaluation examples.
- `spec/factory_bakery/sequel/api_spec.rb` — plain bake, precedence with traits, and plain `_id`-like column examples.
- `spec/factory_bakery/sequel/heuristic_spec.rb` — type-appropriate values, NOT NULL and JSON column examples.
- `spec/factory_bakery/sequel/persistence_spec.rb` — bake vs bake! column round-trip example.
- `spec/factory_bakery/sti_discriminator_spec.rb` — default discriminator, custom discriminator and plain `type` column examples.
- `spec/factory_bakery/uniqueness_spec.rb` — plain, constrained, DB-aware and scoped uniqueness examples (all bake! calls).
- `spec/factory_bakery/associations/all_spec.rb` — uniqueness across auto-built siblings.
- `spec/factory_bakery/associations/collections_spec.rb` — per-child uniqueness on a heuristic attribute.
- `spec/factory_bakery/associations/plugin_spec.rb` — parent heuristics when no parent factory is registered.

### Conditional validators

- Changed constraint discovery so a validator's `if:` / `unless:` conditions are evaluated against the record being baked: complementary presence/absence guards and mutually exclusive formats no longer merge into contradictory constraints, dirty-tracking conditions see the generated attribute as changing, and a raising condition no longer breaks a bake. Record-specific constraints are resolved per bake instead of leaking through the class-level cache.

### String heuristics

- Changed name-derived string generation so identifier-like attributes (`username`, `user_name`, `login`, `handle`, `nickname`, `screen_name`) get identifier-shaped values (`jane_doe42`, matching `\A[a-z][a-z0-9_]{2,19}\z`) instead of person names with spaces. Ordered the attribute-name patterns from most specific to least specific so the generic `/name/` rule no longer shadows `username`; `name`, `first_name` and `display_name` still receive person names. Declared formats and lengths still win, and scalar strings and string array elements share the same logic.

### Numeric generation

- Changed integer generation for wide `numericality` / `comparison` `:in` ranges (and inclusion ranges) to sample from the range bounds instead of materializing them with `to_a`, so ranges such as `-(2**31)..(2**31)` bake instantly. Exclusive-end, endless and beginless ranges and float-bounded ranges on integer columns are supported; parity, `other_than`, exclusions and deterministic small-window filtering are unchanged.

### Regex generation

- Added `FactoryBakery::RegexGeneration` (`lib/factory_bakery/regex_generation/`), a self-contained generator that builds a string a `Regexp` matches by walking its `regexp_parser` syntax tree. It handles literals and escapes, character types, sets (negation, nesting, intersection, POSIX classes), Unicode properties, anchors and `\b`/`\B`, every group form including the absence operator, alternation, all quantifiers, backreferences, lookahead and lookbehind, conditionals, subexpression calls and the `i`/`m`/`x` options. Negated sets and properties never emit a forbidden character. Generation is bounded by depth, step count and output length, the parsed tree is cached per `Regexp`, and the generator accepts length hints and an injectable random source. It depends only on Ruby and `regexp_parser`; an architecture spec parsed with Prism enforces that, and 100% line and branch coverage of the generator is enforced by SimpleCov in the test run.
- Changed `format` validator synthesis to use it. `StringFiller` keeps its verification loop, attempt caps, deadline and exhaustion error; `length` validators and the column limit now reach the generator as length hints. Fixes `/\A[^@\s]+@[^@\s]+\z/` and the Discourse WebHook URI regex (leading lookahead), which previously exhausted their attempts.
- Removed the hand-written `RegexSynthesizer` and the `FFaker::String.from_regexp` regex path.
- Added `regexp_parser` (`~> 2.9`) as a runtime dependency; `simplecov` and `prism` are development dependencies.
- Fixes the formats from issue #49 (`\h` / `\H`, `/i`, leading/trailing `-` in classes, a class's leading range) as part of the same rewrite.

### Associations: core guard-rails (always on)

- Changed heuristics to leave `belongs_to` FK columns (including every component of a composite FK) and polymorphic `*_type` / `*_id` columns unset. Optional associations now bake with `nil` instead of a random dangling value; declarations and call-site overrides still supply values.
- Changed heuristics to leave the STI inheritance column to Rails instead of overwriting the subclass name from `new`, so persisted rows load back as the right class.
- Changed heuristics never to fake Rails-maintained counter caches. A DB default is kept, otherwise a NOT NULL counter without a default gets `0`, otherwise it stays `nil`.
- Changed declaration evaluation so overridden or superseded blocks are never run: the winning layer is picked before any block is evaluated. An association name, its FK components and its polymorphic type column form one alias group with one winner, so `bake(User, account_id: 7)` beats a declared `account` block.
- Changed `bake!` to wrap graph building, nested `bake!` calls and the root `save!` in one savepoint-capable transaction. Any failure now rolls back every row the bake wrote, even when the caller rescues inside an outer transaction.
- Added `FactoryBakery::IncompletePersistenceError` (a `FactoryBakery::Error`), raised when a generated associated record is still unsaved after the root `save!` (for example with `autosave: false`, or `validate: false` on an invalid child). The error names the record and its association and suggests a fix. `bake` stays database-free.
- Added a runaway-nesting backstop: nested `bake` calls past `FactoryBakery.max_bake_depth` (default 10) raise `FactoryBakery::NestingTooDeepError` with the class path instead of `SystemStackError`.
- Changed `association :x` in a definition with no plugin loaded to raise `FactoryBakery::Error` naming `require 'factory_bakery/associations'`, instead of being silently ignored.
- Added a plugin hook API: `FactoryBakery.register_plugin` registers a plugin implementing any subset of `dsl_module` (DSL methods available inside `define` blocks and traits), `heuristic_values(model_klass, context, taken)` (values in the heuristic layer) and `after_instantiate(object, declarations, context)` (runs after all plain values are applied). Plugins compose in registration order, duplicate DSL method names raise, and registration is idempotent. `unregister_plugin` and `reset_plugins!` are available for test isolation.

### Associations: opt-in plugin

- Added persisted parents for raw-FK presence edges (`validates :user_id, presence: true`): the edge is now detected as required separately from association presence, and its parent is given a real id before the owner validates. Under `bake!` the parent is inserted inside the root savepoint (atomic rollback preserved); under `bake` a `:fresh` edge inserts the parent as a documented exception to the unsaved graph, while a `:reuse` miss raises an error naming the edge. Association-presence, polymorphic, `:none`, declaration/override, cycle, depth and back-edge behavior is unchanged.
- Added the opt-in associations plugin, loaded with `require 'factory_bakery/associations'` or, in Rails, `config.factory_bakery.associations` (a Hash of `mode` / `strategy` / `max_depth` / `default_count`, `true`, or a mode symbol; unset or `false` leaves core behavior untouched). The Railtie configures it before loading factory definitions.
- Added three modes: `:none` (explicit declarations only), `:required_only` (the default: required `belongs_to` from a presence validator or NOT NULL FK, recursively) and `:all` (non-polymorphic `belongs_to`, `has_one` and `has_many`). `:all` never walks back the edge it came from and truncates to required-only past `max_depth` (default 2) rather than raising; `default_count` (default 1) bounds collection size. A required polymorphic association with no declaration raises an actionable error.
- Added the `association(name, *traits, factory:, strategy:, count:, **overrides, &owner_block)` DSL: traits, a named or class `factory:`, attribute overrides, `count:` collections, owner-aware blocks and polymorphic targets. The name is validated at bake time; `factory:` is required for polymorphic edges; a block cannot be combined with options and `count:` must be a non-negative Integer on collections only. Precedence is call-site overrides > traits (in application order) > declarations > plugin auto-build > heuristics, across whole alias groups. Literal overrides are applied to every child without uniqueness adjustments.
- Added explicit collection and `has_one` declarations to the associations plugin. `association :comments, count: 3` builds N children (default 1) through the association, applying its create scope (FK, polymorphic type, scope attributes) and verified inverse before the child's heuristics and auto-build run. Owner blocks (`association(:reviewer) { |owner| ... }`) run after all plain attributes are applied; combining a block with options and invalid `count:` values raise `ArgumentError`. `has_many :through` / HABTM via `association` raise a clear "not supported" error, while attribute blocks keep working. `before_add` callbacks and the `bake!` persistence contract apply to collection children.
- Added `strategy: :fresh` (default) and `:reuse` for `belongs_to`: `:reuse` shares completed objects within one bake, then picks the oldest matching row by primary key using the exact STI class, association scope and scalar column overrides, falling back to a fresh build on a miss (unsaved under `bake`). Traits with `:reuse`, explicit use on collections, encrypted or serialized overrides, and missing or composite primary keys raise `ArgumentError`; non-column or non-scalar overrides force a fresh build. Precedence is per-association > `with(strategy:)` > global.
- Added `FactoryBakery::CyclicAssociationError` for required mutual FKs and required self-references, with the reflection path and an opt-out hint; `inverse_of` cannot make an insert cycle persistable. Finite same-class chains ended by a factory declaration keep working.
- Added scoped associations configuration: `FactoryBakery::Associations.with(mode:, strategy:, max_depth:, default_count:) { }` applies fiber-local overrides to the whole nested graph, nests with the inner scope winning, restores previous values in `ensure`, and returns the block's value. The `mode` / `strategy` / `max_depth` / `default_count` readers report the effective scoped-or-global value; global setters and scopes validate known modes, strategies and non-negative integers with clear `ArgumentError`s, and unknown scope keys raise. Added `Associations.reset_configuration!` for test isolation.

### Validator hardening (V1–V7)

- Added DB-aware uniqueness enforcement for heuristic attributes: regenerate on collision using the model's own validator (honoring `scope:`, `case_sensitive:` and conditions), and raise a clear `FactoryBakery::Error` when the value space is exhausted.
- Changed presence handling: presence-validated booleans bake `true`, defaulted columns with a presence validator are filled instead of skipped, and both ActiveModel and ActiveRecord presence validators are recognized.
- Added bake-time resolution of symbol and proc values in comparison and numericality validators against the object being built, including cross-attribute references; unresolved cyclic references fall back to an unconstrained value instead of raising `NoMethodError`.
- Changed inclusion/exclusion validators to evaluate proc and symbol `in:` sets lazily at bake time, once per bake and with the object available; a proc that raises is reported as a contextual `FactoryBakery::Error`.
- Changed format fillers to verify generated strings against the full regex, honor `:without` as well as `:with`, retry within bounds, and raise a clear error instead of returning a non-matching value.
- Changed numeric constraint hygiene: `other_than` is enforced, odd/even parity is re-sampled within the bounds instead of breaching them, and exclusion retries raise on exhaustion rather than returning a forbidden value.
- Added a dedicated filler for `json` / `jsonb` columns that produces JSON-serializable Hash values instead of random strings.

### Test matrix

- Added a CI matrix of Rails 7.1 / 7.2 / 8.0 × SQLite / PostgreSQL / MySQL (`DATABASE_URL`), running the same specs against in-memory SQLite by default and real FK constraints on every adapter. It covers savepoint rollback when the root fails or the caller rescues inside an outer transaction, NOT NULL FK parents inserted first, and `:reuse` lookups; adapter-specific notes are documented in the README.

### Sequel mapper plugin (opt-in)

- Added the opt-in Sequel mapper plugin: `require 'factory_bakery/sequel'` registers a mapper that makes `Sequel::Model` classes bake with the same heuristics (define, traits, named factories, overrides, `bake`, `bake!`). `sequel` stays an optional dependency — the gemspec is unchanged — and when the gem is absent the require raises a helpful `FactoryBakery::Error` naming the Gemfile line to add.
- Added the Sequel constraint mapping: `db_schema` column types (including json-ish db_types), `max_length`, nullability, defaults and parsed `numeric(p, s)` precision/scale feed the existing generators; stored validations under `plugin :validation_class_methods` (`validates_presence_of`, `validates_length_of`, `validates_numericality_of`, `validates_format_of`, `validates_inclusion_of`, `validates_acceptance_of`) map onto the matching ConstraintSet fields.
- Added Sequel uniqueness enforcement: `validates_uniqueness_of` declarations and single-column unique indexes feed the uniqueness flag; the collision check queries the model's own dataset, excluding the record itself, and composite unique indexes never flag a single column.
- Added the Sequel persistence contract: `bake!` saves through Sequel's `save` (which raises on validation failure) wrapped in `db.transaction(savepoint: true)`, so a failure rolls back every row the bake wrote — including nested `bake!` writes — and a declaration that leaves a generated record unsaved raises `FactoryBakery::IncompletePersistenceError`.
- Kept the guard-rail philosophy on Sequel: the primary key and `many_to_one` foreign keys are never auto-filled (alias groups keep an association name and its FK columns together for override precedence), Sequel associations are never auto-built, and counter caches / STI discriminators have no Sequel counterpart to guard. The associations plugin stays on the default mapper's models.
- Documented limits instead of faking them: `plugin :validation_helpers` runs imperatively inside `Model#validate` and is not introspectable as data, so heuristics fall back to schema facts for those models; persisting JSON columns depends on Sequel's `serialization` plugin. The default mapper and the Sequel mapper can be registered in one process, each handling its own classes.
- Added `sequel` as a development-only gem in the root Gemfile (never the gemspec); the Sequel specs run under the root Gemfile and report themselves skipped under the appraisal gemfiles.

## [0.0.2] - 2026-11-18

Complete rewrite of the gem. This release has no compatibility with v0.0.1 or earlier.

- Added heuristic fillers that build valid attribute values from ActiveModel validators and ActiveRecord column types (inclusion, exclusion, length, numericality, comparison, format, acceptance, confirmation, presence, absence, uniqueness hints, enums, and column defaults).
- Added `FactoryBakery.define` for reusable factory definitions with lazy attribute blocks, `trait` (including multiple traits per bake), `initialize_with`, named factories (`define(:name, klass: Model)` and lazy symbol-to-class resolution), and last-one-wins re-registration.
- Added `FactoryBakery.bake` (unsaved) and `FactoryBakery.bake!` (persists when supported), with call-site overrides taking precedence over traits and factory declarations.
- Added support for plain Ruby objects: setters are used for assignment, validator-driven heuristics apply to ActiveModel-compatible objects, attributes with no heuristic information stay `nil`, and `bake!` skips persistence for non-ActiveRecord targets.
- Added definition loading: Rails auto-loads from the first existing `spec/factories`, `test/factories`, or `factories` directory via a Railtie and `config.factory_bakery.definition_paths`; non-Rails apps use `FactoryBakery.definition_paths` and `FactoryBakery.find_definitions`.
- Added the opt-in `FactoryBakery::Methods` module with bare `bake` / `bake!` for RSpec and Minitest. No global functions are installed on `Object` or `Kernel`.
- Removed the generator-era internals and global API; the documented API is now `FactoryBakery.define`, `bake`, `bake!`, `find_definitions`, and `definition_paths`.
- Verified against Rails 7.1, 7.2, and 8.0 on Ruby 3.4.

## [0.1.0] - 2021-03-30

- Initial release
