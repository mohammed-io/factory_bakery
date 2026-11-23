# Test framework wiring

`FactoryBakery::Methods` is the only helper module. It defines exactly two methods, `bake` and `bake!`, and installs nothing globally. Both take the same arguments as `FactoryBakery.bake` and `FactoryBakery.bake!`.

## RSpec

```ruby
# spec/rails_helper.rb (or spec_helper.rb for non-Rails)
require 'factory_bakery/rspec'

RSpec.configure do |config|
  config.include FactoryBakery::Methods
end
```

`require 'factory_bakery/rspec'` makes generated values follow RSpec's seed: `rspec --seed 12345` reproduces a run, and the gem logs `using RSpec seed 12345` once. Without it the seed comes from `FACTORY_BAKERY_SEED`, `FactoryBakery.seed =` (an Integer or a callable), or a random choice per process (logged at WARN). Keep one framework require: the seed has one framework slot, and the last require wins. Run `bin/rails g factory_bakery:install` **before** editing the helper: it writes the require into `config/initializers/factory_bakery.rb` (RSpec when `spec/` exists, else Minitest when `test/` exists), and that file must wrap its body in `if defined?(FactoryBakery::Railtie)` (see [generators-and-rake.md](generators-and-rake.md#install-generator)). If the initializer has the require, add only the `include` in the helper, so the require is not duplicated. The seed is announced once, at INFO when it comes from the framework and at WARN otherwise ([Randomness](../../../docs/guide/configuration.md#randomness)).

Use in examples:

```ruby
let(:user) { bake!(User) }

it 'keeps the email' do
  expect(bake(User, email: 'a@b.test').email).to eq('a@b.test')
end
```

Restrict to some groups: `config.include FactoryBakery::Methods, type: :model`.

## Minitest

```ruby
# test/test_helper.rb (Rails)
require 'factory_bakery/minitest'

class ActiveSupport::TestCase
  include FactoryBakery::Methods
end
```

`require 'factory_bakery/minitest'` makes generated values follow Minitest's seed: `bin/rails test --seed 12345` reproduces a run.

Without Rails:

```ruby
require 'minitest/autorun'
require 'factory_bakery'

class UserTest < Minitest::Test
  include FactoryBakery::Methods

  def test_known_email
    assert_equal 'john@example.com', bake(User, email: 'john@example.com').email
  end
end
```

## Fully qualified calls

Without the include, call `FactoryBakery.bake(...)` and `FactoryBakery.bake!(...)`. A project that is migrating from factory_bot uses this form so call sites stay explicit.

## Transactions and cleanup

- Transactional tests (the Rails default) roll back every `bake!` row. `bake` rows from raw-FK presence edges and `persist: true` roll back too, because they are written inside the test transaction.
- For non-transactional tests (system tests), use `DatabaseCleaner` or an `after` hook, as for any data.
- Bake inside examples (`let`, `before(:each)`), not at file load ([bad pattern](bad-patterns.md#11-baking-at-file-load)).

## Isolation in your own specs

An app suite needs no reset hook. Call nothing between examples. For a setting that one test needs, use a scope that restores itself:

```ruby
FactoryBakery::Associations.with(mode: :all, default_count: 3) { bake!(Post) }
```

`FactoryBakery::Associations.reset_configuration!` restores the **gem's** defaults, not the app's `config.factory_bakery.associations`, so an after-each hook would drop the app's config after the first example. Use it only in specs of your own that assign the plugin's globals themselves and want the defaults back.

`FactoryBakery.reset_plugins!` removes **all** plugins. Do not use it in an app suite unless you register them again ([bad pattern](bad-patterns.md#7-factorybakeryreset_plugins-in-an-app-suite)).

## Speed

Run with YJIT (`RUBY_YJIT_ENABLE=1`). It makes `bake` about 2.2x faster on Ruby 3.4 (`docs/reports/profiling-20261119.md`).

## Verify

```sh
RAILS_ENV=test bin/rails runner 'include FactoryBakery::Methods; ActiveRecord::Base.transaction { record = bake(User); abort FactoryBakery.explain(record) unless record.valid?; p record.class; raise ActiveRecord::Rollback }'
bundle exec rspec        # the suite must pass exactly as before
```
