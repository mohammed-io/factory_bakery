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
| No information | A PORO attribute with no validator | Left `nil` |

This is why a zero-setup `bake(User)` usually produces a valid record: the same validators that check your data are used to generate it. Complex or deliberately unusual values are what factory declarations and traits are for.

## Associations (opt-in plugin)

`require 'factory_bakery/associations'` enables association declarations and required `belongs_to` auto-building:

```ruby
FactoryBakery.define(Post) do
  association :comments, count: 3, body: 'nice'  # has_many: three children bound to this post
  association :profile                           # has_one: one child bound to the owner
  association(:reviewer) { |post| FactoryBakery.bake(User, team: post.team) } # owner-aware escape hatch
end
```

Children are built through the association, so its scope attributes (including the FK and polymorphic type) and its verified inverse are applied before the child's own heuristics run. `count:` must be a non-negative Integer and is only valid on collections; omitting it builds one child. An owner block receives the owner after all plain attributes are applied and cannot be combined with options. `has_many :through` and `has_and_belongs_to_many` are not supported via `association` — assign them with a normal attribute block. `bake!` persists the whole graph, including collection children.

Literal overrides are applied to every child. If an overridden column also has a `uniqueness` validation, the children will collide: FactoryBakery does not make literal values unique. Use a declaration block or leave the value to heuristics when each child needs a distinct value.

### Configuration and scoping

The plugin's defaults are process-wide and validated:

```ruby
FactoryBakery::Associations.mode = :required_only   # :none | :required_only | :all (default)
FactoryBakery::Associations.max_depth = 2           # non-negative Integer (default 2)
FactoryBakery::Associations.default_count = 1       # non-negative Integer (default 1)
```

Invalid modes, negative or non-integer numbers, and unknown scope keys raise `ArgumentError`. The readers (`mode`, `max_depth`, `default_count`) report the *effective* value: the scoped override when one is active, otherwise the global value.

Use `Associations.with` to override settings for one graph. It applies to every bake inside the block, including nested bakes from declaration blocks, is fiber-local (parallel threads and fibers never see each other's scope), nests with the inner scope winning, and restores the previous values even when the block raises. It returns the block's value.

```ruby
FactoryBakery::Associations.mode = :required_only
FactoryBakery::Associations.with(mode: :all, max_depth: 3) do
  FactoryBakery::Associations.mode    # => :all
  FactoryBakery.bake!(Post)           # whole graph built in :all within depth 3
end
FactoryBakery::Associations.mode      # => :required_only
```

`with` takes a block rather than a `bake` keyword because `**overrides` shares its namespace with model attributes: an `associations:` kwarg could collide with a real column. For test isolation, `FactoryBakery::Associations.reset_configuration!` restores the global defaults and clears the current fiber's scope.

## Not supported yet

These are planned, not shipped: sequences, callbacks, and transient attributes. See [docs/associations-design.md](docs/associations-design.md) for the association design.

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
