# Testing recipes

## Wiring

FactoryBakery adds no global methods. `FactoryBakery::Methods` provides bare `bake` and `bake!` and nothing else. It takes the same arguments as `FactoryBakery.bake` / `bake!`.

### RSpec

```ruby
# spec/rails_helper.rb
require 'factory_bakery/rspec'

RSpec.configure do |config|
  config.include FactoryBakery::Methods
end
```

`require 'factory_bakery/rspec'` makes generated values follow RSpec's seed, so `rspec --seed 12345` reproduces a failing run. The gem logs `using RSpec seed 12345` once when it starts drawing values. To pick the seed yourself instead, assign it before any bake: `FactoryBakery.seed = RSpec.configuration.seed` does the same thing. `FACTORY_BAKERY_SEED` still outranks both.

```ruby
RSpec.describe Post do
  it 'is invalid without a title' do
    post = bake(Post, title: nil)

    expect(post).not_to be_valid
  end

  it 'saves with a published trait' do
    post = bake!(Post, :published)

    expect(post.reload).to be_published
  end
end
```

### Minitest

```ruby
# test/test_helper.rb
require 'factory_bakery/minitest'

class ActiveSupport::TestCase
  include FactoryBakery::Methods
end
```

`require 'factory_bakery/minitest'` makes generated values follow Minitest's seed, so `bin/rails test --seed 12345` reproduces a failing run. Without it the seed comes from `FACTORY_BAKERY_SEED`, `FactoryBakery.seed =` (an Integer or a callable), or a random choice made once per process. See [Randomness](configuration.md#randomness).

```ruby
class PostTest < ActiveSupport::TestCase
  test 'bakes a post with a known title' do
    post = bake(Post, title: 'Hello')

    assert_equal 'Hello', post.title
  end
end
```

Outside Rails, include the module in `Minitest::Test` or your own base class.

## Data per example

Bake inside the example, not at load time. A bake at file load runs before your transactional fixtures start, and its rows outlive the example.

```ruby
# bad: runs when the file loads
POST = FactoryBakery.bake!(Post)

# good
let(:post) { bake!(Post) }
```

Under transactional tests, every `bake!` row rolls back with the example. `bake` rows in the raw-FK and `persist: true` cases roll back too, because they are written inside the test transaction.

Without transactional tests (system tests, `use_transactional_tests = false`), clean up as you would for any data: `DatabaseCleaner` or an `after` hook.

## Recipes

### A list of records

There is no `create_list`. Use Ruby:

```ruby
posts = Array.new(3) { bake!(Post, :published) }
```

### Distinct values per record

An attribute block runs per bake, so give it a generator:

```ruby
FactoryBakery.define(Post) do
  title { "Post #{SecureRandom.hex(4)}" }
end
```

Or leave the column to inference. Uniqueness-validated columns are regenerated on collision.

### Test a validation

`bake` returns invalid records. Override the field and ask the model:

```ruby
user = bake(User, email: 'not-an-email')
expect(user).not_to be_valid
expect(user.errors[:email]).to include('is invalid')
```

### Test with an unsaved model

```ruby
post = bake(Post)      # unsaved, associations built unsaved (required_only)
post.save!             # saves the graph through ActiveRecord autosave
```

Prefer `bake!` when the test needs saved rows: it verifies the graph and raises on failure; with `FactoryBakery.savepoints = true` it also rolls back.

### Build only what the test is about

Override the attribute, keep the rest inferred:

```ruby
let(:comment) { bake!(Comment, body: 'first!') }
```

The `post` it belongs to is built by the plugin in `required_only` mode.

### Build a specific graph

Pass the objects you already have. Passing `post:` suppresses auto-building that edge.

```ruby
let(:post)     { bake!(Post) }
let(:comments) { Array.new(2) { bake!(Comment, post: post) } }
```

### Change the mode for one test

```ruby
it 'bakes the whole graph' do
  FactoryBakery::Associations.with(mode: :all) do
    post = bake!(Post)
    expect(post.comments).not_to be_empty
  end
end
```

### Several records of one class that must differ

Two edges to the same class build two records under the default `:fresh` strategy. With `:reuse_non_unique` they can share one, except on unique edges. See [Associations](associations.md#strategies).

### Attribute hash for a request spec

There is no `attributes_for`. A small helper gives the closest thing (verified):

```ruby
# spec/support/bakery_helpers.rb
module BakeryHelpers
  def attributes_for(klass, *traits, **overrides)
    FactoryBakery.bake(klass, *traits, **overrides)
      .attributes.except('id', 'created_at', 'updated_at').compact
  end
end
```

It returns column values for the bake, so required attributes are present and optional ones are absent. It does not include association objects. Its keys are strings.

## Performance

A bake is mostly method dispatch and small lookups.

- Run with YJIT. On Ruby 3.4 it makes `bake` about 2.2 times faster (`docs/reports/profiling-20261119.md`). `RUBY_YJIT_ENABLE=1` or `ruby --yjit`.
- `bake` is much cheaper than `bake!`. Prefer it when the test does not need a row.
- Keep `:required_only` as your default mode. `:all` builds optional children and collections, so a test that does not need them pays for them.
- `strategy: :reuse_non_unique` can save inserts by sharing lookup parents, at the cost of reading the database and coupling tests to existing rows.
- A polymorphic target that must be discovered can trigger one `Rails.application.eager_load!` per process. Set `eager_load = false` in tests that manage their own loading, or declare the target.
- Declare a hot, expensive definition once instead of baking the same parent in every example. A `before(:all)` row would leak across examples. Use `let` plus a cheap override instead.

## Debugging a failing bake

1. Try `FactoryBakery.bake(Model)` in a console, then `.valid?` and `.errors.full_messages`.
2. Try `bake!` to see the persistence error.
3. Look the message up in [diagnostics.md](../../skills/factory-bakery-diagnostics/references/diagnostics.md).
4. In Rails, run `bin/rails 'factory_bakery:doctor[Model]'`. It repeats steps 1 and 2 for you, rolled back, and prints the first error with a link to the matching catalog entry.
