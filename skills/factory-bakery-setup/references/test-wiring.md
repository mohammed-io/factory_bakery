# Test framework wiring

`FactoryBakery::Methods` is the only helper module. It defines exactly two methods, `bake` and `bake!`, and installs nothing globally. Both take the same arguments as `FactoryBakery.bake` and `FactoryBakery.bake!`.

## RSpec

```ruby
# spec/rails_helper.rb (or spec_helper.rb for non-Rails)
RSpec.configure do |config|
  config.include FactoryBakery::Methods
end
```

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
class ActiveSupport::TestCase
  include FactoryBakery::Methods
end
```

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
- Bake inside examples (`let`, `before(:each)`), not at file load.

## Isolation in your own specs

If specs of your own register plugins or change settings:

```ruby
config.after { FactoryBakery::Associations.reset_configuration! }   # restores plugin defaults
```

`FactoryBakery.reset_plugins!` removes **all** plugins. Do not use it in an app suite unless you register them again.

## Speed

Run with YJIT (`RUBY_YJIT_ENABLE=1`). It makes `bake` about 2.2x faster on Ruby 3.4 (`docs/reports/profiling-20261119.md`).

## Verify

```sh
bin/rails runner -e test 'include FactoryBakery::Methods; p bake(User).class'
bundle exec rspec        # the suite must pass exactly as before
```
