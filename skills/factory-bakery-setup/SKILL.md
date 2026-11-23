---
name: factory-bakery-setup
description: Installs and configures the FactoryBakery gem (factory_bakery) in a Ruby or Rails project. Covers the Gemfile group, the definitions directory, config.factory_bakery.* settings, the associations, attachments and Sequel plugins, RSpec or Minitest wiring including the seed integration, the install and definition generators, and a factory_bakery:doctor check. Use when the user wants to add, install, wire up, configure or verify FactoryBakery, including a loose request like "set up test data generation with FactoryBakery". Not for moving factory_bot, fabrication, machinist or fixtures over (use factory-bakery-migrate) and not for a bake that raises, returns an invalid record or leaves a value nil (use factory-bakery-diagnostics).
---

# Set up FactoryBakery

Goal: `FactoryBakery.bake(Model)` works, definitions load from one known directory, tests can call it, and the verification in step 8 passed.

Human guide: [`getting-started.md`](../../docs/guide/getting-started.md), [`rails.md`](../../docs/guide/rails.md), [`configuration.md`](../../docs/guide/configuration.md).

## Rules

- Setup is additive. Do not delete or rewrite existing test setup, and do not touch the user's uncommitted changes. If the working tree is dirty, work in a worktree: `git worktree add ../<repo>-bakery-setup -b factory-bakery-setup`.
- Gem in the test groups only. Never in the default or production group.
- If another factory library is installed, FactoryBakery gets its **own** definitions directory (step 4).
- Do not invent options, commands or messages. If a command is missing in the installed gem version, say so and do the step by hand.
- Search with the project's code-search tool (`tgrep` when an index exists).
- Before finishing, read [`references/bad-patterns.md`](references/bad-patterns.md) and check the change against it.

## Procedure

### 1. Inspect the project

| Question | How |
| --- | --- |
| Ruby >= 3.2? | `.ruby-version`, `.tool-versions`, `ruby -v` |
| Rails 7.1, 7.2 or 8.0 (for ActiveRecord)? | `Gemfile.lock` |
| ORM | ActiveRecord, Sequel, plain ActiveModel |
| Test framework | RSpec (`spec/`), Minitest (`test/`) |
| Existing factory library | `factory_bot`, `fabrication`, `machinist`, fixtures |
| File attachments | Active Storage, Paperclip / kt-paperclip |
| Existing definition directories | `spec/factories`, `test/factories`, `factories` |

If the user also wants to move off a factory library, finish this setup first, then hand over to `factory-bakery-migrate`.

### 2. Install the gem

```ruby
# Gemfile
group :development, :test do
  gem 'factory_bakery', git: 'https://github.com/mohammed-io/factory_bakery.git'
end
```

Run `bundle install` and confirm it resolves.

### 3. Configure

Rails, in `config/application.rb` (or `config/environments/test.rb`). All options: [`references/rails-config.md`](references/rails-config.md).

```ruby
config.factory_bakery.associations = { mode: :required_only }
```

Outside Rails:

```ruby
require 'factory_bakery'
require 'factory_bakery/associations'      # opt in to association building
FactoryBakery.definition_paths = ['spec/bakery']
FactoryBakery.find_definitions
```

| Associations mode | Use when |
| --- | --- |
| setting omitted | The project never wants graphs built (a required `belongs_to` stays `nil`) |
| `:required_only` | Default choice. Models have required `belongs_to` |
| `:all` | Never globally. Per test: `FactoryBakery::Associations.with(mode: :all) { ... }` |

### 4. Pick the definitions directory

| Situation | Directory |
| --- | --- |
| No other factory library | `spec/factories` or `test/factories`. Rails finds it with no config |
| `factory_bot` (or another) present | `spec/bakery` or `test/bakery`, and `config.factory_bakery.definition_paths = [...]` stated explicitly |

Never under `app/` or any autoload path. `bin/rails g factory_bakery:install` (step 7) creates the directory and, when it detects factory_bot, writes the `definition_paths` line.

### 5. Plugins to require

| The app has | Add |
| --- | --- |
| Active Storage `has_one_attached`, or Paperclip | `require 'factory_bakery/attachments'` in a test-env initializer or at the top of a definition file |
| Sequel models | `require 'factory_bakery/sequel'` |
| Associations outside Rails | `require 'factory_bakery/associations'` (in Rails the config in step 3 does it) |

### 6. Wire the tests

Details: [`references/test-wiring.md`](references/test-wiring.md).

```ruby
# spec/rails_helper.rb
require 'factory_bakery/rspec'      # generated values follow rspec --seed N
RSpec.configure { |config| config.include FactoryBakery::Methods }

# test/test_helper.rb (Minitest apps: require 'factory_bakery/minitest' instead)
class ActiveSupport::TestCase
  include FactoryBakery::Methods
end
```

`bin/rails g factory_bakery:install` already writes the framework `require` into `config/initializers/factory_bakery.rb` (RSpec when `spec/` exists, else Minitest when `test/` exists). If the initializer has it, add only the `include`. Keep one framework require.

Seed resolution order: `FACTORY_BAKERY_SEED`, then `FactoryBakery.seed =` (Integer or callable), then the framework seed from the require above, then a random seed per process. The gem logs which one it used (INFO for the framework, WARN for the others). See [Randomness](../../docs/guide/configuration.md#randomness).

### 7. Generators and rake tasks (Rails)

Details: [`references/generators-and-rake.md`](references/generators-and-rake.md).

```sh
bin/rails g factory_bakery:install            # initializer + definitions directory
bin/rails g factory_bakery:definition Post    # one stub
bin/rails factory_bakery:definitions          # stubs for every concrete model without a class-keyed definition
```

Existing files are skipped, never overwritten, unless the user asks for `--force`. If `bin/rails g --help` does not list `factory_bakery:install`, create the directory and files by hand.

### 8. Verify

Run in order. Stop at the first failure.

1. Load check (Rails):
   ```sh
   bin/rails runner -e test 'p FactoryBakery::VERSION, FactoryBakery::PluginRegistry.plugins.size, FactoryBakery.definition_paths'
   ```
   With the associations config the plugin count is `1`. `definition_paths` must list the directory from step 4.
2. One bake: `bin/rails runner -e test 'p FactoryBakery.bake(User).valid?'`
3. Doctor, every concrete model, rolled back:
   ```sh
   RAILS_ENV=test NO_FAIL=1 bin/rails factory_bakery:doctor
   ```
   `NO_FAIL=1` keeps exit status `0` so the report is not a command failure. The last line is `N valid, M needs definition`. Fix nothing yet. List the failing models with their hint links.
4. Run the project's existing suite. It must pass exactly as before. Setup alone changes no test.

Failures from doctor go to the `factory-bakery-diagnostics` skill. Each usually needs one definition line, and a model that already bakes needs none.

### 9. Report

Tell the user what was added (gem, config, directory, helper include, seed require), which plugins are on, the doctor counts and failing models, and every file changed. Offer next steps: stubs for failing models (`WRITE=1 NO_FAIL=1 bin/rails factory_bakery:doctor`), or a migration from factory_bot.

## Bad patterns (top ones)

Full list with before/after code: [`references/bad-patterns.md`](references/bad-patterns.md).

| Do not | Do instead |
| --- | --- |
| Put the gem in the default group | `group :development, :test` |
| Let FactoryBakery and factory_bot load one directory | `spec/bakery` plus `definition_paths` |
| Set `associations = :all` globally | `:required_only`, and `Associations.with(mode: :all) { }` in the one test |
| `require 'factory_bakery/associations'` by hand when the Rails config already enables it | The config only |
| Skip `require 'factory_bakery/rspec'` / `'/minitest'` | One framework require, so `--seed N` reproduces values |
| Hard-code `FactoryBakery.seed = 1234` in CI | `FACTORY_BAKERY_SEED=1234` for the one run that reproduces a failure |
| Call `FactoryBakery.reset_plugins!` in an app suite | `FactoryBakery::Associations.reset_configuration!` |
| Put definitions under `app/` | A test directory outside the autoload paths |
| Set `generators = true` next to factory_bot | Leave it unset. `true` replaces factory_bot's generator hook |
| Define on `Object` or `ApplicationRecord` for a global default | One definition per model |

## References

| File | Use |
| --- | --- |
| [`references/rails-config.md`](references/rails-config.md) | Railtie order, every `config.factory_bakery.*` option, plugin settings |
| [`references/test-wiring.md`](references/test-wiring.md) | RSpec and Minitest helpers, seed require, transactions, isolation |
| [`references/generators-and-rake.md`](references/generators-and-rake.md) | Generators, rake tasks, reading doctor output |
| [`references/troubleshooting.md`](references/troubleshooting.md) | Symptoms of a broken setup |
| [`references/bad-patterns.md`](references/bad-patterns.md) | Setup mistakes with reasons and fixes |

A bake that fails: [`factory-bakery-diagnostics`](../factory-bakery-diagnostics/SKILL.md) and its [catalog](../factory-bakery-diagnostics/references/diagnostics.md). Moving from factory_bot: [`factory-bakery-migrate`](../factory-bakery-migrate/SKILL.md).
