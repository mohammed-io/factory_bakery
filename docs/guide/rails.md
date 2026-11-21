# Rails

FactoryBakery ships a Railtie, plus generators and rake tasks. The Railtie lives in `lib/factory_bakery/active_record_mapper/railtie.rb` and is defined when Rails is loaded before the gem (always true in a normal app boot).

## What the Railtie does

At boot (`config.after_initialize`), in this order:

1. If `config.factory_bakery.associations` is set (and not `false`), require `factory_bakery/associations` and configure it. This happens **before** definitions load, so definitions can use `association`.
2. If `config.factory_bakery.fill_optional` is set (not `nil`), assign it to `FactoryBakery.fill_optional`.
3. Resolve the definition paths and load every `*.rb` under them.

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
| `fill_optional` | `true`, `false` or an Array of attribute names. Applied to `FactoryBakery.fill_optional` at boot. Unset leaves the core default (`false`) |
| `definition_paths` | A String or an Array. Relative paths resolve against `Rails.root`. When set, it replaces the default lookup |
| `generators` | `true`, `false` or unset. Controls the model generator hook. See [Model generator hook](#model-generator-hook) |

If `definition_paths` is unset, **one** directory is chosen, relative to `Rails.root`:

1. **factory_bot detected**: `spec/bakery` (`test/bakery` for Minitest). factory_bot counts as detected when the `FactoryBot` constant is defined, or when a `*.rb` file under `spec/factories`, `test/factories` or `factories` has a line that starts with `FactoryBot.define`.
2. Otherwise the first **existing** of `spec/factories`, `test/factories`, `factories`.
3. If none exists: `spec/factories` or `test/factories` (not created, nothing to load).

`spec` or `test` follows the generators' test framework: `spec` for `:rspec`, `test` for any other framework. With no test framework configured, `spec` when a `spec/` directory exists, else `test`.

Only the chosen directory is loaded. If it does not exist, nothing is loaded and nothing raises. The same rule picks where the generators and `factory_bakery:definitions` write (see [Definition generator](#definition-generator)).

### Things to know

- Definitions load **once at boot**, in every environment where the gem is loaded. Put the gem in `:development, :test` (or `:test` only) so production does not load it.
- Loading a definition that names a model (`FactoryBakery.define(User)`) autoloads that model during boot. Use a bare symbol (`define(:user)`) if you need the file to load before the model exists: the class is resolved at the first bake. `klass: User` references the constant at load time.
- Class-keyed definitions refer to the class object that existed when the file loaded. With code reloading, that object goes stale. Tests normally do not reload. Symbol factories without `klass:` re-resolve on every bake. (Read from the code, not run.)
- `config.factory_bakery.definition_paths` reads the value at boot. Setting it in an initializer is fine because the hook runs after initializers.
- RSpec and Minitest behave identically. Neither needs a `require`.

## Definitions directory when factory_bot is present

factory_bot's documented default paths include `spec/factories` and `test/factories`. These are the directories FactoryBakery would otherwise use. When factory_bot is detected (see above), FactoryBakery already defaults to `spec/bakery` or `test/bakery`. State the directory anyway, so the choice is visible in the config:

```ruby
config.factory_bakery.definition_paths = [Rails.root.join('spec/bakery').to_s]
```

`bin/rails g factory_bakery:install` writes this line for you when it detects factory_bot. See [Migrating from factory_bot](migrating-from-factory-bot.md#step-2-set-up-side-by-side).

## Generators

### Model generator hook

```sh
bin/rails g model Post title:string
bin/rails g scaffold Post title:string
```

Both also write a definition stub (`bin/rails g model` and the model step of `scaffold`):

```ruby
# test/factories/post.rb (the definitions directory, one file per model)
# frozen_string_literal: true

FactoryBakery.define(Post) do
  # title { "MyString" }
end
```

The stub lists each attribute as a commented example. A reference becomes `# user { FactoryBakery.bake(User) }`. A polymorphic reference becomes `# subject { FactoryBakery.bake(SomeModel) }`. A namespaced model `Admin::Post` is written to `admin/post.rb`.

The hook uses Rails' `fixture_replacement` slot, so while it is active Rails does not write a fixtures file. `config.factory_bakery.generators` controls it:

| Setting | Effect |
| --- | --- |
| unset | The hook is on, unless the app already selects another `fixture_replacement` (for example `:factory_bot`). That choice is kept |
| `true` | The hook is on. It **replaces** any other `fixture_replacement` |
| `false` | The hook is off. If `fixture_replacement` was set to `:factory_bakery`, it is cleared. Another gem's choice is left alone, and Rails writes its fixtures file again |

- Disable for one run: `--skip-factory-bakery` (also `--no-factory-bakery`).
- The setting is read when generators load. It needs a test framework in `config.generators` (a normal Rails app has one).

### Install generator

```sh
bin/rails g factory_bakery:install
```

Creates `config/initializers/factory_bakery.rb` and the definitions directory. An existing initializer is skipped. Pass `--force` to overwrite it.

The initializer lists `associations`, `definition_paths`, `fill_optional` and `generators` as commented examples.

- **factory_bot detected** (same test as above): it creates `spec/bakery` (`test/bakery` for Minitest) and writes an active `config.definition_paths = ["spec/bakery"]` line, so the two gems never load each other's files.
- **Otherwise**: it creates the directory FactoryBakery would load (an existing `spec/factories`, `test/factories` or `factories`, else `spec/factories` or `test/factories`) and leaves `definition_paths` commented.

### Definition generator

```sh
bin/rails g factory_bakery:definition Post
bin/rails g factory_bakery:definition Admin::Post title:string user:references
```

Writes `<definitions dir>/post.rb` for one model, with the same commented attribute examples as the model hook. The directory is the **first** entry of `config.factory_bakery.definition_paths` when it is set, else the default directory chosen above. An existing file is skipped. Pass `--force` to overwrite it.

## Rake tasks

```sh
bin/rails 'factory_bakery:definitions[Post,Comment]'   # named models
bin/rails factory_bakery:definitions                   # every concrete model without a class-keyed definition
bin/rails 'factory_bakery:doctor[Post,Admin::Post]'    # named models
bin/rails factory_bakery:doctor                        # every concrete model
WRITE=1 NO_FAIL=1 bin/rails factory_bakery:doctor      # write stubs for failing models, exit 0
```

Names are Active Record class names. A name that is not a concrete Active Record model aborts the task with `Unknown concrete Active Record model: <name>`. With no names, both tasks eager-load the app and cover every concrete model (abstract classes are skipped).

- `definitions` writes the same stubs as the definition generator, into the same directory. A file that already exists is skipped. With no names it skips models that already have a registered class-keyed definition.
- `doctor` checks each model twice: `bake` then `valid?`, then `bake!`, which must persist the record. Each probe, and the whole run, is rolled back on every Active Record connection pool registered for the current role. Model callbacks and validators still run, so any effect they have outside the database (jobs, HTTP, files) still happens. Run it in the test environment.

`doctor` prints one line per failing model (the first error only), then a summary:

```
Post: Title can't be blank — Check the model validations and callbacks, then declare any required overrides. (https://github.com/mohammed-io/factory_bakery/blob/main/docs/diagnostics.md#domain-rules-inference-cannot-know)
Comment: could not generate a unique value for Comment#code: ... — Declare a value that varies across bakes. (https://github.com/mohammed-io/factory_bakery/blob/main/docs/diagnostics.md#unique-value-collisions)
12 valid, 2 needs definition
```

Each line ends with a link to the matching entry in the [diagnostics catalog](../diagnostics.md).

| Control | Effect |
| --- | --- |
| exit status | `1` when any model fails, `0` when all pass |
| `NO_FAIL=1` | Report only: exit `0` even when models fail |
| `WRITE=1` | Also write a stub for each failing model, with the error message as comment lines at the top. An existing file is kept |

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
