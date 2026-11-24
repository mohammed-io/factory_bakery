---
name: factory-bakery-setup
description: Install and configure FactoryBakery in a Ruby or Rails project. Use when the user wants to add FactoryBakery (factory_bakery gem) to an app or gem, wire it into RSpec or Minitest, choose definition directories, enable the associations or attachments plugins, set Rails config (config.factory_bakery.*), run the install/definition generators or rake tasks, or verify the setup with `factory_bakery:doctor`. Not for migrating from factory_bot (use factory-bakery-migrate) or fixing a failing bake (use factory-bakery-diagnostics).
---

# Set up FactoryBakery

Goal: a project where `FactoryBakery.bake(Model)` works, definitions load from a known directory, tests can call it, and a verification step has passed.

Guide pages for every step: [`docs/guide/getting-started.md`](../../docs/guide/getting-started.md), [`rails.md`](../../docs/guide/rails.md), [`configuration.md`](../../docs/guide/configuration.md).

## Rules

- Do not touch the user's uncommitted changes. If the working tree is dirty, work in a separate git worktree on its own branch: `git worktree add ../<repo>-bakery-setup -b factory-bakery-setup`.
- Do not delete or rewrite existing test setup. Setup is additive.
- If `factory_bot` (or another factory library) is installed, use a **separate definitions directory** (see step 4). Do not let two libraries load the same directory.
- Add the gem to the test groups only. Not to production.
- Use the project's code-search tool (`tgrep` when an index exists) to inspect the project.

## Procedure

### 1. Inspect the project

Find out, and write down:

| Question | How |
| --- | --- |
| Ruby version (needs >= 3.2) | `.ruby-version`, `.tool-versions`, `ruby -v` |
| Rails? Version (needs 7.1, 7.2 or 8.0 for ActiveRecord) | `Gemfile.lock` |
| ORM | ActiveRecord, Sequel, plain ActiveModel |
| Test framework | RSpec (`spec/`), Minitest (`test/`) |
| Sorbet | `sorbet/` directory or `sorbet` in `Gemfile.lock` |
| Existing factory library | `factory_bot`, `fabrication`, `machinist`, fixtures |
| File attachments | Active Storage, Paperclip / kt-paperclip |
| Existing definitions directories | `spec/factories`, `test/factories`, `factories` |

If a factory library exists and the user wants to move off it, stop and use the `factory-bakery-migrate` skill after setup.

### 2. Install the gem

```ruby
# Gemfile
group :development, :test do
  gem 'factory_bakery', git: 'https://github.com/mohammed-io/factory_bakery.git'
end
```

Run `bundle install`. Confirm it resolves.

If the project uses Sorbet, optionally copy the gem's `rbi/factory_bakery.rbi` into the project's `sorbet/rbi/shims/`. See the Sorbet instructions in [`references/test-wiring.md`](references/test-wiring.md#sorbet).

### 3. Configure

Rails: add to `config/application.rb` (or `config/environments/test.rb` to limit it to tests). Details: [`references/rails-config.md`](references/rails-config.md).

```ruby
config.factory_bakery.associations = { mode: :required_only }
# config.factory_bakery.definition_paths = [Rails.root.join('spec/bakery').to_s]
```

Non-Rails:

```ruby
require 'factory_bakery'
require 'factory_bakery/associations'            # opt in to association building
FactoryBakery.definition_paths = ['spec/bakery']
FactoryBakery.find_definitions
```

Choose the associations mode:

| Mode | Use when |
| --- | --- |
| omit the setting | The project never wants graphs built for it |
| `:required_only` (recommended default) | Models have required `belongs_to` |
| `:all` | Only for specific tests, via `FactoryBakery::Associations.with(mode: :all) { ... }` |

### 4. Pick the definitions directory

| Situation | Directory |
| --- | --- |
| No factory library | `spec/factories` (RSpec) or `test/factories` (Minitest). Rails finds it with no config |
| `factory_bot` present | `spec/bakery` or `test/bakery`, plus `config.factory_bakery.definition_paths = [...]`. Rails defaults to this directory when it detects factory_bot, but state it explicitly |

`bin/rails g factory_bakery:install` (step 7) creates the directory and, for factory_bot, writes the `definition_paths` line. By hand: create the directory, and add an empty `.keep` if the project ignores empty directories.

### 5. Plugins to require

| If the app has | Add |
| --- | --- |
| Active Storage `has_one_attached`, or Paperclip | `require 'factory_bakery/attachments'` in an initializer (test env) or at the top of a definition file |
| Sequel models | `require 'factory_bakery/sequel'` |
| Association building outside Rails | `require 'factory_bakery/associations'` |

In Rails, associations are enabled by the config in step 3. Do not also `require` it by hand.

### 6. Wire the tests

Opt in to `bake` and `bake!` helpers. Details: [`references/test-wiring.md`](references/test-wiring.md).

```ruby
# spec/rails_helper.rb
require 'factory_bakery/rspec' # generated values follow RSpec's seed (rspec --seed N)
RSpec.configure { |config| config.include FactoryBakery::Methods }

# test/test_helper.rb (Minitest apps instead: require 'factory_bakery/minitest')
class ActiveSupport::TestCase
  include FactoryBakery::Methods
end
```

The seed is one of: `FACTORY_BAKERY_SEED`, `FactoryBakery.seed =` (an Integer, or a callable returning one), the framework's seed above, or a random one per process. The gem logs which one it used. See [Randomness](../../docs/guide/configuration.md#randomness).

### 7. Generators and rake tasks

Details: [`references/generators-and-rake.md`](references/generators-and-rake.md).

```sh
bin/rails g factory_bakery:install            # initializer + definitions directory
bin/rails g factory_bakery:definition Post    # one stub
bin/rails factory_bakery:definitions          # stubs for every concrete model without a class-keyed definition
```

Existing files are skipped, never overwritten, unless the user asks for `--force`. If those commands do not exist in the installed gem version (`bin/rails g --help` lists `factory_bakery:install`), create the directory and the files by hand. Do not invent options.

### 8. Verify

Run the checks in order. Stop at the first failure.

1. Load check:
   ```sh
   bin/rails runner -e test 'p FactoryBakery::VERSION, FactoryBakery::PluginRegistry.plugins.size, FactoryBakery.definition_paths'
   ```
   With the associations config the plugin count is `1`.
2. A single bake:
   ```sh
   bin/rails runner -e test 'p FactoryBakery.bake(User).valid?'
   ```
3. Doctor (all concrete models, rolled back):
   ```sh
   RAILS_ENV=test NO_FAIL=1 bin/rails factory_bakery:doctor
   ```
   `NO_FAIL=1` keeps the exit status `0` so the report is not treated as a command failure. Without it, any failing model exits `1`. The last line is `N valid, M needs definition`. Fix nothing yet. List the failing models with their hint links.
4. Run the project's existing test suite. It must pass exactly as before the setup. Setup alone changes no test.

If the doctor lists failures, hand the list to the `factory-bakery-diagnostics` skill. Each failure usually needs one definition line.

### 9. Report

Tell the user: what was added (gem, config, directory, helper include), which plugins are on, the doctor result (counts and the failing models), and the exact files changed. Offer next steps: generate stubs for failing models (`WRITE=1 NO_FAIL=1 bin/rails factory_bakery:doctor`), or migrate from factory_bot.

## Troubleshooting

See [`references/troubleshooting.md`](references/troubleshooting.md). For a bake error, use the [`factory-bakery-diagnostics`](../factory-bakery-diagnostics/SKILL.md) skill and its [catalog](../factory-bakery-diagnostics/references/diagnostics.md).
