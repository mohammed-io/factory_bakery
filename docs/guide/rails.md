# Rails

FactoryBakery ships a Railtie, plus generators and rake tasks. The Railtie lives in `lib/factory_bakery/active_record_mapper/railtie.rb` and is defined when Rails is loaded before the gem (always true in a normal app boot).

## What the Railtie does

At boot (`config.after_initialize`), in this order:

1. If `config.factory_bakery.associations` is set (and not `false`), require `factory_bakery/associations` and configure it. This happens **before** definitions load, so definitions can use `association`.
2. Resolve the definition paths and load every `*.rb` under them.

Also, on every boot and code reload (`config.to_prepare`), it clears the polymorphic-target cache, so cached candidates never point at stale constants.

## Configuration

```ruby
# config/application.rb (or config/environments/test.rb)
config.factory_bakery.associations     = { mode: :required_only }
config.factory_bakery.definition_paths = [Rails.root.join('spec/bakery').to_s]
```

| Option | Meaning |
| --- | --- |
| `associations` | Unset or `false`: core only. `true`: plugin with defaults. A mode symbol or a Hash (`mode`, `strategy`, `max_depth`, `default_count`, `eager_load`). Unknown keys raise `ArgumentError` |
| `definition_paths` | A String or an Array. When set, it replaces the conventional lookup |
| `generators` | `false` disables the model generator hook. See below |

If `definition_paths` is unset, the first **existing** directory among these is used, relative to `Rails.root`:

1. `spec/factories`
2. `test/factories`
3. `factories`

Only that one directory is loaded. If none exists, nothing is loaded and nothing raises.

### Things to know

- Definitions load **once at boot**, in every environment where the gem is loaded. Put the gem in `:development, :test` (or `:test` only) so production does not load it.
- Loading a definition that names a model (`FactoryBakery.define(User)`) autoloads that model during boot. Use a bare symbol (`define(:user)`) if you need the file to load before the model exists: the class is resolved at the first bake. `klass: User` references the constant at load time.
- Class-keyed definitions refer to the class object that existed when the file loaded. With code reloading, that object goes stale. Tests normally do not reload. Symbol factories without `klass:` re-resolve on every bake. (Read from the code, not run.)
- `config.factory_bakery.definition_paths` reads the value at boot. Setting it in an initializer is fine because the hook runs after initializers.
- RSpec and Minitest behave identically. Neither needs a `require`.

## Definitions directory when factory_bot is present

factory_bot's documented default paths include `spec/factories` and `test/factories`. These are the same directories FactoryBakery loads. Both gems would evaluate the other's files. Use a separate directory for FactoryBakery while both are installed:

```ruby
config.factory_bakery.definition_paths = [Rails.root.join('spec/bakery').to_s]
```

See [Migrating from factory_bot](migrating-from-factory-bot.md#step-2-set-up-side-by-side).

<!-- verify against implementation -->
## Generators

The generators and rake tasks below are described by the contract the implementation follows. Check them against the code before relying on exact output.

### Model generator hook

```sh
bin/rails g model Post title:string
```

also writes a definition stub at `<definitions dir>/post.rb`:

```ruby
FactoryBakery.define(Post) do
end
```

- On by default, like factory_bot_rails.
- Disable globally: `config.factory_bakery.generators = false`.
- Disable for one run: `--skip-factory-bakery`.
- It does not replace another gem's `fixture_replacement`. Opt in explicitly if you want that.

### Install generator

```sh
bin/rails g factory_bakery:install
```

Creates the initializer and the definitions directory. With factory_bot present it uses `spec/bakery` or `test/bakery` instead of `spec/factories` or `test/factories`.

### Definition generator

```sh
bin/rails g factory_bakery:definition Post
```

Writes a stub for one model.

## Rake tasks

```sh
bin/rails factory_bakery:definitions[Post,Comment]   # no args: every model without a definition
bin/rails factory_bakery:doctor[Post]                # default: all models
WRITE=1 bin/rails factory_bakery:doctor              # write stubs for failing models
```

- `definitions` writes stubs for the models you name. With no arguments it covers every model that has no definition yet.
- `doctor` bakes each model with `bake` plus `valid?`, and with `bake!`. Everything is rolled back. For each failure it prints the error, a hint and a link to an anchor in [diagnostics.md](../../skills/factory-bakery-diagnostics/references/diagnostics.md). With `WRITE=1` it writes a stub definition for each failing model.

Quote the task with brackets in zsh: `bin/rails 'factory_bakery:doctor[Post]'`.

## Test helpers

Include `FactoryBakery::Methods` in `spec/rails_helper.rb` (RSpec) or `test/test_helper.rb` (Minitest). See [Testing recipes](testing-recipes.md).

## A minimal Rails setup

```ruby
# Gemfile
group :development, :test do
  gem 'factory_bakery', git: 'https://github.com/mohammed-io/factory_bakery.git'
end

# config/application.rb
config.factory_bakery.associations = { mode: :required_only }

# spec/rails_helper.rb
RSpec.configure { |config| config.include FactoryBakery::Methods }
```

Verify it:

```sh
bin/rails runner -e test 'p FactoryBakery::PluginRegistry.plugins.size; p FactoryBakery.definition_paths'
```

With the associations plugin configured, the first number is `1`.
