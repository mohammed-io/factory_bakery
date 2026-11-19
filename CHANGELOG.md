## [Unreleased]

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
