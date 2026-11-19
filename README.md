# FactoryBakery

FactoryBakery builds fully populated test objects **from your model's own metadata**. Validators and database column types decide what goes into each attribute; factory definitions are a thin customization layer for the few attributes a test actually cares about.

The gem is inspired by Python's [model-bakery](https://pypi.org/project/model-bakery/). It is deliberately **not** a [factory_bot](https://github.com/thoughtbot/factory_bot) mirror: you do not describe every attribute. You describe the exceptions, and heuristics fill the rest.

```ruby
user = FactoryBakery.bake(User, email: 'john@example.com')
user.email # => "john@example.com" — every other attribute was filled heuristically
```

## Requirements

- Ruby >= 3.2
- Rails 7.1, 7.2, or 8.0

## Installation

Add this line to your application's Gemfile. The gem is installed from git for now:

```ruby
gem 'factory_bakery', git: 'https://github.com/mohammed-io/factory_bakery.git'
```

Then run:

```sh
bundle install
```

## Quick start

`require 'factory_bakery'` is all the setup there is. `bake` returns an unsaved object; `bake!` calls `save!` when the object supports it.

```ruby
require 'factory_bakery'

user = FactoryBakery.bake(User)
user.new_record? # => true

user = FactoryBakery.bake!(User)
user.persisted? # => true

# Override just the value under test; everything else is still filled.
user = FactoryBakery.bake(User, email: 'john@example.com')
user.email # => "john@example.com"
```

Overrides are keyword arguments. Several can be passed at once, and attributes you do not pass keep their heuristic values. Baking a class requires no factory definition and no configuration.

## Factory definitions

Register a definition once, in any file loaded by your app or test suite:

```ruby
FactoryBakery.define(User) do
  name  { 'Ada Lovelace' }
  email { "user#{rand(1_000_000)}@example.com" }

  trait :admin do
    role { 'admin' }
  end

  trait :vip do
    role  { 'vip' }
    level { 'gold' }
  end
end
```

Attribute values are **lazy blocks**: `name { 'Ada Lovelace' }` rather than `name: 'Ada Lovelace'`. The block is evaluated on every bake, so repeated bakes get fresh values (which is how uniqueness-validated columns stay unique). There is no static-value shorthand.

Apply the definition by baking the class, optionally with traits and overrides:

```ruby
FactoryBakery.bake(User)                         # base definition
FactoryBakery.bake(User, :admin)                 # base + :admin
FactoryBakery.bake(User, :admin, :vip)           # base + :admin + :vip
FactoryBakery.bake(User, :admin, name: 'Grace')  # overrides beat every trait
```

Traits are applied in the order given, so later traits win for overlapping attributes. In `bake(User, :admin, :vip)`, `role` ends up `'vip'`. Precedence for any attribute is:

> call-site overrides > traits (in application order) > factory declaration blocks > heuristics

Undeclared attributes are still filled heuristically. Requesting an unknown trait raises `FactoryBakery::Error`, as does baking an unregistered symbol.

### Constructors: `initialize_with`

When a constructor needs arguments, declare them with `initialize_with`. It accepts a hash:

```ruby
class Invoice
  attr_reader :number

  def initialize(number:)
    @number = number
  end
end

FactoryBakery.define(Invoice) do
  initialize_with(number: 'INV-001')
end

FactoryBakery.bake(Invoice).number # => "INV-001"
```

For a class with a zero-argument constructor (including most POROs), the same hash is applied through setters. For an ActiveRecord model it is passed to `new` as attributes.

### Named factories

Definitions can be keyed by a symbol instead of a class. Use `klass:` to bind the name to a class explicitly:

```ruby
FactoryBakery.define(:customer, klass: User) do
  name { 'Ada' }
end

FactoryBakery.bake(:customer) # => a User named 'Ada'
```

A bare symbol resolves its class lazily at the **first bake**, by camelizing the symbol (`:admin_user` becomes `AdminUser`). This lets definition files load before the application models exist:

```ruby
# spec/factories/admin_users.rb — may be loaded before AdminUser is defined
FactoryBakery.define(:admin_user) do
  name { 'Admin' }
end

# Later, once the constant exists:
FactoryBakery.bake(:admin_user) # => an AdminUser
```

If the constant cannot be resolved, `FactoryBakery::Error` is raised naming the symbol; the failure is not cached, so a later bake succeeds once the constant exists. Class and symbol registrations are independent keys, and re-registering either one replaces the previous definition silently (last one wins).

## Plain Ruby objects (POROs)

ActiveRecord is not required. Any object with setters can be a target: declared attributes and overrides are assigned through those setters, and `bake!` simply returns the object if it has no `save!` method.

```ruby
class Contact
  attr_accessor :name, :email, :note
end

FactoryBakery.define(Contact) do
  name { 'Ada' }
end

contact = FactoryBakery.bake(Contact, email: 'ada@example.com')
contact.name  # => "Ada"
contact.email # => "ada@example.com"
contact.note  # => nil (no declaration, override, or heuristic information)

FactoryBakery.bake!(Contact) # => a Contact, with no persistence attempted
```

POROs that include `ActiveModel::Model` / `ActiveModel::Validations` also get validator-driven heuristics for their undeclared attributes. With no schema and no validators, attributes that have no value supplied are left `nil` rather than raising.

## Definition loading

### In Rails

Definition files are loaded automatically after the application initializes. FactoryBakery uses the first existing directory among:

1. `spec/factories`
2. `test/factories`
3. `factories`

All `*.rb` files under it are loaded recursively, so the usual test-framework layouts work without any `require`. To use a different location, set the paths in `config/application.rb` (or an environment file):

```ruby
config.factory_bakery.definition_paths = [Rails.root.join('custom/factories').to_s]
```

A single string is accepted as well as an array. This works identically under RSpec and Minitest.

### Outside Rails

Set the paths yourself and call `find_definitions`:

```ruby
FactoryBakery.definition_paths = ['spec/factories', 'test/factories']
FactoryBakery.find_definitions
```

Nonexistent paths are skipped, and calling `find_definitions` again re-evaluates the files, which makes reloading safe.

## In your test suite

FactoryBakery never installs global `bake` methods. Opt in with `FactoryBakery::Methods` — the same module in both frameworks.

**RSpec** — in `spec/spec_helper.rb`:

```ruby
RSpec.configure do |config|
  config.include FactoryBakery::Methods
end
```

```ruby
RSpec.describe User do
  it 'bakes a user with a known email' do
    user = bake(User, email: 'john@example.com')

    expect(user.email).to eq('john@example.com')
  end
end
```

**Minitest** — include it in your test class (or a shared base class):

```ruby
require 'minitest/autorun'
require 'factory_bakery'

class UserTest < Minitest::Test
  include FactoryBakery::Methods

  def test_bakes_a_user_with_a_known_email
    user = bake(User, email: 'john@example.com')

    assert_equal 'john@example.com', user.email
  end
end
```

Both `bake` and `bake!` are available bare after the include, with exactly the same arguments as `FactoryBakery.bake` / `FactoryBakery.bake!`. You can always use the fully qualified module methods instead.

## How heuristics work

For each attribute not supplied by a declaration, a trait, or an override, FactoryBakery picks a filler. ActiveRecord models contribute their column types; any ActiveModel-compatible object contributes its validators. The filler then reads the validator options to produce a valid value:

| Metadata | Example | Result |
| --- | --- | --- |
| Column type | `title: :string`, `count: :integer`, `published_at: :datetime` | A type-appropriate fake value (strings come from [FFaker](https://github.com/ffaker/ffaker)) |
| `inclusion` | `inclusion: { in: %w[pending done] }` | One of the allowed values |
| `exclusion` | `exclusion: { in: %w[www ftp] }` | A generated value outside the forbidden set |
| `length` | `length: { is: 5 }`, `{ in: 3..8 }` | A string padded or truncated to the required length |
| `numericality`, `comparison` | `greater_than: 18`, `in: 1..10` | A number inside the permitted bounds |
| `format` | `with: /\A[a-z]+\z/` | A string generated from the regex where possible |
| `acceptance` | `acceptance: { accept: 'yes' }` | The accepted value |
| `confirmation` | `confirmation: true` on `password` | `password_confirmation` is copied from `password`; overriding the source propagates |
| `presence`, `absence` | `presence: true`, `absence: true` | A non-blank value, or `nil` |
| `enum` | `enum status: { pending: 0, done: 1 }` | One of the defined enum keys |
| Column default | `default: 'draft'` | Left to the database; the database default is kept |
| Primary key | `id` | Skipped |
| `belongs_to` foreign keys and polymorphic pairs | `account_id`, `commentable_type` / `commentable_id` | Left `nil`; a made-up row or class name would dangle |
| STI inheritance column | `type` | Left to Rails (the subclass's name, or `nil` on the base) |
| Counter cache | `comments_count` | Left to Rails: the DB default is kept, else `0` if NOT NULL with no default, else `nil` |
| No information | A PORO attribute with no validator | Left `nil` |

This is why a zero-setup `bake(User)` usually produces a valid record: the same validators that check your data are used to generate it. Complex or deliberately unusual values are what factory declarations and traits are for.

## Associations

Core never invents relationship values. The opt-in plugin builds associated objects for you when you want a whole graph; without it, associations are yours to declare explicitly. See [docs/associations-design.md](docs/associations-design.md) for the design rationale.

### Without the plugin

Heuristics fill columns from validators and column types, but they cannot know which row a foreign key should point to or which class a polymorphic type names. Core therefore leaves `belongs_to` foreign keys (including every component of a composite FK) and polymorphic `*_type` / `*_id` columns `nil`, leaves the STI inheritance column to Rails, and never fakes Rails-maintained counter caches. Declarations, traits and call-site overrides still supply values as usual. Optional FKs stay `nil` instead of getting a random dangling integer.

Write an association by hand with an attribute block. It is lazy, so it runs once per bake:

```ruby
FactoryBakery.define(User) do
  account { FactoryBakery.bake(Account) } # unsaved parent; `bake` never writes to the database
end

user = FactoryBakery.bake(User)
user.account # => an unsaved Account
```

Only the winning declaration is evaluated. An association name, its FK columns and its polymorphic type column form one alias group, so `bake(User, account_id: 7)` or `bake(User, account: existing)` stops the `account` block before it does any work — including an INSERT if the block had called `bake!`. The same applies when a trait redeclares an edge. Precedence is unchanged:

> call-site overrides > traits (in application order) > factory declaration blocks > heuristics

`account { nil }` (or `comments { [] }`) in a trait or at the call site opts an edge out without a separate DSL.

**Persistence contract.** `bake!` wraps graph building, nested `bake!` calls and the root `save!` in one transaction opened with `requires_new`: a savepoint when your code already has a transaction. Any failure rolls back every row the bake wrote, even if you rescue the error in an outer transaction. After the root saves, every generated record is verified. A record that would silently stay unsaved — for example with `autosave: false` or `validate: false` on an invalid child — makes `bake!` raise `FactoryBakery::IncompletePersistenceError` and roll back. The error names the record and its association; persist that record explicitly in a declaration or override, or fix the association's autosave/validate options. Non-ActiveRecord targets skip persistence as before, and `bake` stays database-free — apart from [raw-FK presence edges](#raw-fk-presence-edges), the documented exception below.

**Depth backstop.** Runaway nested bakes raise `FactoryBakery::NestingTooDeepError` with the class path instead of `SystemStackError`. `FactoryBakery.max_bake_depth` defaults to 10; raise it for legitimately deep graphs.

### Loading the plugin

```ruby
require 'factory_bakery/associations'
```

Requiring the file registers the plugin and enables the `association` DSL. Without it, `association :x` in a definition raises `FactoryBakery::Error` naming the require, instead of being silently ignored.

In Rails, configure it in `config/application.rb` (or an environment file). The Railtie loads and configures the plugin before factory definitions are loaded, so definitions may use `association`:

```ruby
config.factory_bakery.associations = { mode: :required_only } # omitted keys keep their defaults
# config.factory_bakery.associations = true                   # all defaults
# leaving it unset (or false) keeps core behavior
```

The hash accepts `mode`, `strategy`, `max_depth` and `default_count`; a bare mode symbol such as `:all` is accepted too. Unknown keys and invalid values raise `ArgumentError`.

### Modes

| Mode | Auto-builds (unless declared or overridden) | Never auto-builds |
| --- | --- | --- |
| `:none` | Nothing; only explicit `association` declarations | Everything else |
| `:required_only` (default) | Required `belongs_to`, recursively (presence validator on the association name **or the raw FK column**, or a NOT NULL FK) | Optional `belongs_to`, `has_one`, `has_many`, through / HABTM; optional polymorphic |
| `:all` | Every non-polymorphic `belongs_to` (optional too), `has_one` (one child), `has_many` (`default_count`) | Through / HABTM, optional polymorphic |

"Required" follows your model and schema: a presence validator on the association name — including `on: :create` and conditional validators — or a NOT NULL FK column counts. A presence validator on the raw FK column also counts, and is tracked separately because it changes the persistence contract (see below). Plain ActiveRecord outside Rails defaults `belongs_to` to optional, so specs using it must say `optional: false` when they mean required. A required polymorphic `belongs_to` with no declaration raises an actionable error asking for `factory:`.

Two rules keep `:all` bounded. It **never walks back the edge it came from**: a child of `post.comments` is bound to that post rather than growing a second one. And greater `max_depth` (default 2) **truncates `:all` to required-only** rather than raising, so objects stay valid. The root bake is depth 1, so with the default its direct associations are built; deeper hops keep only required parents. `default_count` (default 1) is the number of children per `has_many` in `:all` and when `count:` is omitted; `has_one` always builds one.

```ruby
FactoryBakery::Associations.with(mode: :all, default_count: 3) do
  FactoryBakery.bake!(Post) # direct associations plus three comments per post
end
```

#### Raw-FK presence edges

`validates :user_id, presence: true` validates the **column**, not the association. An unsaved auto-built parent has a nil id, so its FK stays nil and the record is invalid. When an edge's required signal is the raw FK column (a presence validator, not merely a NOT NULL schema constraint), the plugin gives the parent a real id before the owner is validated:

| Contract | Behavior |
| --- | --- |
| `bake!` | Creates the parent **inside the root savepoint** and sets the FK from its id. The insert rolls back atomically with the rest of the graph if anything fails. NOT NULL + real FK constraints are satisfiable end-to-end. |
| `bake` (`:fresh`, the default) | Creates the parent and **inserts a row outside the unsaved contract**. This is the documented exception to "`bake` never writes": the raw column cannot be satisfied any other way. The root record itself stays unsaved. |
| `bake` with `:reuse` | An existing database row is reused without writing. On a miss the plugin raises `FactoryBakery::Error` naming the edge and suggesting `bake!`, a declaration, or an explicit FK/assignment — the reuse strategy promises not to insert on a miss. |
| `bake!` with `:reuse` | An existing row is reused; on a miss a fresh parent is created inside the savepoint. |

Association-presence edges (`validates :user, presence: true`, `optional: false`) are unaffected: their parent stays unsaved under `bake` with zero INSERTs. Polymorphic edges keep their existing behavior (a raw FK signal never auto-builds them). Cycle detection, `max_bake_depth`, back-edge suppression, declarations and overrides all apply to the persisted-parent path as they do anywhere else; an explicit `user:` or `user_id:` at the call site suppresses it entirely.

### The `association` DSL

```ruby
association(name, *traits, factory: nil, strategy: nil, count: nil, **overrides, &owner_block)
```

```ruby
FactoryBakery.define(Post) do
  association :author                                          # reflection class, its factory + heuristics
  association :category, :featured, name: 'News'                # traits and overrides for the child
  association :editor, factory: :admin_user                     # named factory (class also accepted)
  association :commentable, factory: :post                      # polymorphic target: factory: is required
  association :comments, count: 3, body: 'nice'                 # has_many: three children bound to this post
  association :cover                                            # has_one: one child bound to the owner
  association(:reviewer) { |post| FactoryBakery.bake(User, team: post.team) }
end
```

- The name is checked against `reflect_on_association` at **bake time**, not definition time, so definition files can load before models. A typo raises `FactoryBakery::Error` naming the model and association.
- Traits are forwarded to the child bake in order; `factory:` names a registered symbol or a class compatible with the reflection (a subclass is fine) and is mandatory for polymorphic targets. Overrides are forwarded too and beat the child's own factory declarations. Literal overrides are applied to **every** child: if the column also has a `uniqueness` validation, the children collide, because FactoryBakery does not make literal values unique. Use a block or leave the value to heuristics when each child needs a distinct value.
- `count:` must be a non-negative Integer and is only valid on collections; `0` builds an empty, loaded collection, and omitting it builds one child. An owner block receives the owner after all plain attributes have been applied, assigns its whole return value, and cannot be combined with options. A block plus options, an invalid `count:` and an invalid `strategy:` raise `ArgumentError`.
- Children are built through the association, so its create scope (FK, polymorphic type, scope attributes) and its verified inverse are applied before the child's heuristics and auto-building run, and `bake!` persists the whole graph. `has_many :through` and `has_and_belongs_to_many` are not supported via `association` (they raise a clear error); assign them with a normal attribute block.
- Precedence across all of the above is:

  > call-site overrides > traits (in application order) > declarations > plugin auto-build > heuristics

  A later trait redeclaration replaces the base declaration. Likewise, a call-site override of `author` **or** `author_id` suppresses both the declaration and mode auto-building for that edge.

**Strategies: `:fresh` and `:reuse`.** `:fresh` is the default: every edge bakes a new target (unsaved under `bake`, inserted by autosave under `bake!`). With `:reuse`, a `belongs_to` takes an existing object instead:

| | `:reuse` lookup |
| --- | --- |
| In the same bake | A completed matching object is shared before the database is queried — e.g. `order.user` and `order.shop.user` are the same record. Ancestors still being built are never shared. |
| In the database | Exact STI class + association scope + scalar column overrides from the declaration, oldest row by primary key (deterministic). |
| On a miss | Falls through to an ordinary fresh build: unsaved under `bake`, inserted under `bake!` via autosave. [Raw-FK presence edges](#raw-fk-presence-edges) are the exception: they raise under `bake` and are created inside the savepoint under `bake!`. |

```ruby
FactoryBakery.define(Post) do
  association :category, strategy: :reuse # share the lookup row, or build one if none matches
end
```

Settings are most-specific-first: per-association `strategy:` > `Associations.with(strategy:)` > global `Associations.strategy = :fresh`. `:reuse` applies to `belongs_to` only: an explicit setting on a collection raises `ArgumentError`, while an inherited scoped/global setting quietly skips ineligible edges. Traits with `:reuse` raise. Only scalar, column-backed overrides are matched; non-column or non-scalar overrides force a fresh build, while encrypted or serialized overrides and a missing or composite primary key raise `ArgumentError`. `factory:` is applied on a miss only and still names a polymorphic target.

`:reuse` reads the database even under `bake` and picks whatever row is already there, so it couples tests to existing data. String matches can also be case-insensitive on MySQL — see [Adapter notes](#adapter-notes).

### Cycles and nesting

Auto-building required edges can revisit a reflection path. A mutual required `belongs_to` pair, a required self-reference, or any loop raises `FactoryBakery::CyclicAssociationError` with the full path and an opt-out hint; `inverse_of` does not make an insert cycle persistable. Break the loop by declaring one side (`owner { nil }`) or making one side optional. Finite same-class chains ended by a factory declaration still work. An acyclic chain that exceeds `max_bake_depth` raises `FactoryBakery::NestingTooDeepError` as described above.

### Configuration and scoping

The plugin's defaults are process-wide and validated:

```ruby
FactoryBakery::Associations.mode = :required_only   # :none | :required_only | :all (default)
FactoryBakery::Associations.strategy = :fresh       # :fresh (default) | :reuse
FactoryBakery::Associations.max_depth = 2           # non-negative Integer (default 2)
FactoryBakery::Associations.default_count = 1       # non-negative Integer (default 1)
```

Invalid modes, strategies, negative or non-integer numbers, and unknown scope keys raise `ArgumentError`. The readers (`mode`, `strategy`, `max_depth`, `default_count`) report the *effective* value: the scoped override when one is active, otherwise the global value.

Use `Associations.with` to override settings for one graph. It applies to every bake inside the block, including nested bakes from declaration blocks, is fiber-local (parallel threads and fibers never see each other's scope), nests with the inner scope winning, and restores the previous values even when the block raises. It returns the block's value.

```ruby
FactoryBakery::Associations.with(mode: :all, max_depth: 3) do
  FactoryBakery::Associations.mode # => :all
  FactoryBakery.bake!(Post)        # whole graph built in :all within three levels
end
FactoryBakery::Associations.mode   # => the global mode again
```

`with` takes a block rather than a `bake` keyword because `**overrides` shares its namespace with model attributes: an `associations:` kwarg could collide with a real column. For test isolation, `FactoryBakery::Associations.reset_configuration!` restores the global defaults and clears the current fiber's scope.

### Adapter coverage

The same association specs run in the 3 × 3 CI matrix — Rails 7.1 / 7.2 / 8.0 × SQLite / PostgreSQL / MySQL — against real foreign-key constraints (a dangling insert must raise `ActiveRecord::InvalidForeignKey`), transaction and savepoint rollback, NOT NULL FK parents inserted first, and `:reuse` database lookups. See [Full Rails × database matrix](#full-rails--database-matrix) and [Adapter notes](#adapter-notes) for how to run each combination locally and for adapter-specific behavior.

### Coming from factory_bot

| factory_bot | FactoryBakery |
| --- | --- |
| `association :author` | `association :author` (after requiring the plugin, or with Rails config) |
| `association :author, :admin, factory: :editor, name: 'Ann'` | Same spelling: traits, `factory:` and overrides |
| `create_list(:comment, 3, post: post)` | `association :comments, count: 3` inside the owner's definition |
| `use_parent_strategy` / build vs create strategy | `bake` builds the whole graph unsaved; `bake!` persists the whole graph in one transaction |

## Sequel support

`Sequel::Model` classes bake with the same heuristics through an opt-in mapper plugin:

```ruby
require 'factory_bakery/sequel'
```

The require registers a Sequel mapper that claims `Sequel::Model` descendants only; the default mapper keeps handling its own models in the same process. `sequel` stays an **optional dependency** — the gemspec never requires it. If the gem is missing, the require raises a helpful `FactoryBakery::Error` telling you to add `gem 'sequel'` to your Gemfile.

What maps:

| Sequel | Result |
| --- | --- |
| `db_schema` column types (`integer`, `string`, `text`, `float`, `decimal`, `date`, `datetime`, `time`, `boolean`, json-ish db types) | A type-appropriate fake value through the same generators the default mapper feeds |
| Column `max_length`, nullability, defaults, `numeric(10, 2)` db_types | Length bound, nullability, database default kept, precision/scale |
| Stored validations (`plugin :validation_class_methods`: `validates_presence_of`, `validates_length_of`, `validates_numericality_of`, `validates_format_of`, `validates_inclusion_of`, `validates_acceptance_of`) | The matching constraint fields (presence, length, numericality, format, inclusion, acceptance) |
| `validates_uniqueness_of` and single-column unique indexes | Uniqueness flag + dataset-backed collision check (regeneration, exhaustion error) |
| `many_to_one` reflections | Guard columns + alias groups: FKs stay `nil`, never auto-built |
| `bake!` | Sequel's `save` (raises on validation failure) inside `db.transaction(savepoint: true)`, with the same rollback and verify contract as the default mapper |

Out of scope, documented rather than faked:

- **`plugin :validation_helpers` declarations are not introspectable.** They run imperatively inside `Model#validate` — code, not data — so heuristics fall back to schema facts for those models. Use `plugin :validation_class_methods` (Sequel's reflective declaration API) when you want validator-driven generation.
- **Sequel associations are never auto-built.** `many_to_one` foreign keys stay `nil`; assign the associated object yourself in an attribute block. The opt-in associations plugin above works against the default mapper's models and answers its clear "not supported" error on Sequel classes.
- Persisting JSON columns depends on Sequel's `serialization` plugin — a model-level concern outside the mapper.

## Not supported yet

These are planned, not shipped: sequences, callbacks, and transient attributes. Associations are shipped as the opt-in plugin described above; [docs/associations-design.md](docs/associations-design.md) records the design decisions and rationale.

## Development

After checking out the repo, run `bin/setup` to install dependencies. Run the linter with `bundle exec rubocop`.

The Railtie requires Rails at load time, so `rails` (plus `pg` and `mysql2`, so any adapter can be selected from any gemfile) are development dependencies in the root `Gemfile`. That fixes plain `bundle exec rspec`, which previously failed with `cannot load such file -- rails`. The alternative — making the Railtie require conditional — was rejected because the Railtie specs boot a real `Rails::Application` and would still need Rails installed.

### Rails matrix on in-memory SQLite

One command runs every supported Rails version against in-memory SQLite:

```bash
mise exec -- bundle exec appraisal rspec
```

A single version can be run with `BUNDLE_GEMFILE=gemfiles/rails8.0.gemfile bundle exec rspec`, or with the root Gemfile via `bundle exec rspec` (Rails 8.x). With no `DATABASE_URL`, foreign-key enforcement is enabled on the SQLite connection and there are no skips.

### Full Rails × database matrix

`DATABASE_URL` selects the adapter for the whole suite; in-memory SQLite remains the default. The same specs, macros and tables run on all three databases.

```bash
# PostgreSQL
DATABASE_URL=postgres://localhost/factory_bakery_test \
  BUNDLE_GEMFILE=gemfiles/rails8.0.gemfile mise exec -- bundle exec rspec

# MySQL (utf8mb4)
DATABASE_URL='mysql2://root@127.0.0.1/factory_bakery_test?encoding=utf8mb4' \
  BUNDLE_GEMFILE=gemfiles/rails8.0.gemfile mise exec -- bundle exec rspec
```

Local throwaway servers can be started with Docker:

```bash
docker run -d --name fb_pg -e POSTGRES_PASSWORD=postgres \
  -e POSTGRES_DB=factory_bakery_test -p 55432:5432 postgres:16-alpine
docker run -d --name fb_my -e MYSQL_ROOT_PASSWORD=root \
  -e MYSQL_DATABASE=factory_bakery_test -p 53306:3306 mysql:8.4
```

CI runs the 3 × 3 matrix (Rails 7.1 / 7.2 / 8.0 × SQLite / PostgreSQL / MySQL) with service containers; see `.github/workflows/test-matrix.yml`.

| Rails (resolved) | SQLite | PostgreSQL | MySQL |
| --- | --- | --- | --- |
| 7.1 (7.2.3) | ✅ | ✅ | ✅ |
| 7.2 (7.2.3) | ✅ | ✅ | ✅ |
| 8.0 (8.1.2) | ✅ | ✅ | ✅ |

### Adapter notes

- Real FK constraints are asserted on every adapter by attempting a dangling insert and expecting `ActiveRecord::InvalidForeignKey`. SQLite needs `PRAGMA foreign_keys = ON`; PostgreSQL and MySQL enforce FKs by default. Table cleanup drops children before parents so FK-constrained tables can be removed.
- PostgreSQL uses `jsonb` for adapter-appropriate JSON columns; `json` has no equality operator, so a uniqueness-validated JSON column uses `jsonb` there.
- MySQL uses `utf8mb4`. Its case-insensitive collation means `:reuse` string matches can be case-insensitive, unlike SQLite/PostgreSQL. JSON columns also cannot be compared to a bound string without `CAST(... AS JSON)`, so ActiveRecord's uniqueness validator cannot observe a duplicate JSON payload on MySQL; the uniqueness spec documents that behavior instead of faking a collision.
- The `rails7.1` appraisal currently resolves Rails 7.2.3 (its constraint is `~> 7.1, >= 7.1`); the resolved versions are shown in the table above.

## Contributing

Bug reports and pull requests are welcome at https://github.com/mohammed-io/factory_bakery. Everyone participating is expected to follow the [code of conduct](CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](LICENSE.txt).
