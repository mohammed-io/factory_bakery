# Getting started

## Requirements

- Ruby >= 3.2
- Rails 7.1, 7.2 or 8.0 for ActiveRecord models. The core also runs without Rails (see [Sequel and ActiveModel](sequel-and-activemodel.md)).

## Install

The gem is installed from git for now. Put it in the groups that run your tests:

```ruby
# Gemfile
group :development, :test do
  gem 'factory_bakery', git: 'https://github.com/mohammed-io/factory_bakery.git'
end
```

```sh
bundle install
```

In a Rails app, requiring the gem registers the ActiveRecord mapper and the Railtie. Nothing else is needed for a first bake.

## Your first bake

`bake` builds an unsaved object. `bake!` builds and saves it.

```ruby
user = FactoryBakery.bake(User)
user.new_record? # => true
user.name        # filled, because the column is NOT NULL
user.bio         # nil: optional, nothing needs it

user = FactoryBakery.bake!(User)
user.persisted? # => true
```

You did not write a definition. FactoryBakery read the `User` columns and validators and filled what a valid record needs. See [Heuristics](heuristics.md) for the exact rules.

## Override what the test cares about

Overrides are keyword arguments:

```ruby
user = FactoryBakery.bake(User, email: 'john@example.com')
user.email # => "john@example.com"
```

`bake` does not check your overrides. If you pass `email: 'not-an-email'` and the model validates the format, you get an invalid record back. `bake!` then raises `ActiveRecord::RecordInvalid`.

## Add a definition when inference is not enough

Create a file in `spec/factories`, `test/factories` or `factories` (Rails loads it automatically; see [Rails](rails.md)):

```ruby
# spec/factories/user.rb
FactoryBakery.define(User) do
  name { 'Ada Lovelace' }

  trait :admin do
    role { 'admin' }
  end
end
```

Attribute values are blocks. The block runs on every bake.

```ruby
FactoryBakery.bake(User)          # name is 'Ada Lovelace'
FactoryBakery.bake(User, :admin)  # role is 'admin'
```

Only declare what inference cannot produce or what a test asserts on. Everything else stays automatic.

## Use it in tests

FactoryBakery never adds global methods. Include the module you want:

```ruby
# spec/rails_helper.rb
RSpec.configure do |config|
  config.include FactoryBakery::Methods
end
```

```ruby
RSpec.describe User do
  it 'keeps the email we gave it' do
    user = bake!(User, email: 'john@example.com')

    expect(user.reload.email).to eq('john@example.com')
  end
end
```

Minitest works the same way: `include FactoryBakery::Methods` in your test class or base class. More in [Testing recipes](testing-recipes.md).

## Build a graph of records

Associations are not built until you opt in. Without the plugin, a required `belongs_to` is left `nil` and the record is invalid. Load the plugin:

```ruby
# config/application.rb (Rails)
config.factory_bakery.associations = { mode: :required_only }
```

```ruby
# outside Rails
require 'factory_bakery/associations'
```

Then `bake(Comment)` also builds the post it needs. See [Associations](associations.md).

## Check the whole app

With the generators and rake tasks (see [Rails](rails.md)):

```sh
bin/rails factory_bakery:doctor
```

This bakes every concrete Active Record model, with `bake` and `valid?` and then with `bake!`, rolls everything back, and prints the models that fail with a hint and a link into the [diagnostics catalog](../diagnostics.md) for each. It ends with a count (`12 valid, 2 needs definition`) and exits with status `1` if any model failed. Add `NO_FAIL=1` to always exit `0`, or `WRITE=1` to write a stub definition for each failing model.

## Next

- Saving, transactions and verification: [`bake` vs `bake!`](bake-vs-bake-bang.md).
- Which value wins: [Overrides and precedence](overrides-and-precedence.md).
- Moving from factory_bot: [Migrating from factory_bot](migrating-from-factory-bot.md).
