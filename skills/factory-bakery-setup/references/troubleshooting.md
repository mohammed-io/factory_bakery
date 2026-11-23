# Setup troubleshooting

For an error raised by a bake, use the [`factory-bakery-diagnostics`](../../factory-bakery-diagnostics/SKILL.md) skill and its [catalog](../../factory-bakery-diagnostics/references/diagnostics.md). This page covers problems with the setup itself.

| Symptom | Cause | Fix |
| --- | --- | --- |
| `NameError: uninitialized constant FactoryBakery`, `NoMethodError: undefined method 'factory_bakery'` for the Rails config, or `cannot load such file -- factory_bakery/rspec` (or `/minitest`) | Gem not in the bundle for this environment. At production boot, an unguarded initializer or a `config.factory_bakery` line in `config/application.rb` | Check the Gemfile group. Run `bundle install`. Run the command with the right `RAILS_ENV`. Guard the initializer with `if defined?(FactoryBakery::Railtie)` and move config to `config/environments/test.rb` ([bad pattern](bad-patterns.md#15-factorybakery-config-or-requires-where-the-gem-is-not-loaded)) |
| `NameError: undefined local variable or method 'config'`, or a `NoMethodError` on `definition_paths=`, raised by `config/initializers/factory_bakery.rb` | The line used the environment-file form. `config` is the app config only in `config/environments/*.rb` and `config/application.rb`; an initializer file has none, and inside the generated `tap` block `config` is already the factory_bakery options | In the initializer write `Rails.application.config.factory_bakery.…`, or `config.definition_paths = …` inside the generated `tap` block ([rails-config.md](rails-config.md#options)) |
| `cannot load such file -- factory_bakery/associations` | Old gem version, or not bundled | The fix for old versions is in the current source (0.0.2.0, still Unreleased in CHANGELOG.md; nothing is on rubygems.org): a path: checkout has it; on git:, move `ref:`. Check `bundle exec` |
| `` `association` requires the associations plugin: require 'factory_bakery/associations' `` | Plugin not enabled | Add `config.factory_bakery.associations = {...}` (Rails) or the require |
| Definitions never apply | Wrong directory. `FactoryBakery.definition_paths` is empty or points elsewhere | Print it. Create the directory. Set `config.definition_paths` inside the generated initializer's `tap` block, or `Rails.application.config.factory_bakery.definition_paths` |
| Definitions apply twice or `NoMethodError` at boot | factory_bot and FactoryBakery both load `spec/factories` | Separate directory: `RAILS_ENV=test bin/rails g factory_bakery:install`, or `spec/bakery` plus `definition_paths`. Rails defaults to `spec/bakery` only when it detects factory_bot ([bad pattern](bad-patterns.md#2-factorybakery-and-factory_bot-loading-one-directory)) |
| `NameError: uninitialized constant Admin::Post` at boot, from a definitions file | A class-keyed stub names a missing model, e.g. `RAILS_ENV=test bin/rails g factory_bakery:definition Admin::Post` for a class that does not exist: `define(Admin::Post)` resolves the constant when the file loads | Fix the name, or delete the stub |
| `bake` is undefined in tests | `FactoryBakery::Methods` not included | See [test-wiring.md](test-wiring.md), or call `FactoryBakery.bake` |
| Attachments are not attached | Attachments plugin not required | `require 'factory_bakery/attachments'` |
| Sequel model gets no auto-built associations | Not supported for Sequel | Assign in an attribute block |
| `factory_bakery:doctor` is not found | The installed gem predates the rake tasks, or the gem is in `group :test` only, so not loaded in development | Run the task with `RAILS_ENV=test`. For an old gem, use a `path:` checkout or a ref that has it (nothing is on rubygems.org), or skip the doctor step and bake models by hand |
| `bin/rails g model` writes no FactoryBakery stub | Another `fixture_replacement` (for example `:factory_bot`) is selected, `config.factory_bakery.generators = false`, or `--skip-factory-bakery` was passed | Run `RAILS_ENV=test bin/rails g factory_bakery:definition Post`. To make the hook win, set `config.factory_bakery.generators = true` (ask first: it replaces the other choice) |
| `factory_bakery:doctor` exits `1` in a script | A model failed. That is the default | `NO_FAIL=1` for report only. Read the failing lines |
| `factory_bakery:doctor` or `definitions` prints `Unknown concrete Active Record model: X` | The name is not a concrete Active Record class (a typo, an abstract class, a non-model) | Fix the name. With no names the task skips abstract classes itself |
| Boot is slow or loads all models | A polymorphic edge triggered `eager_load!` | Set `eager_load: false`, or declare the polymorphic target |
| Definitions are ignored after reload | Class-keyed definitions go stale | Re-run `FactoryBakery.find_definitions`, or use a symbol factory |
| Plugins vanish between examples | Something calls `FactoryBakery.reset_plugins!` | Do not call it in an app suite, or register again after ([bad pattern](bad-patterns.md#7-factorybakeryreset_plugins-in-an-app-suite)) |
| `ArgumentError` at boot naming an associations option | Wrong key or value in `config.factory_bakery.associations` | Valid keys: `mode`, `strategy`, `max_depth`, `default_count`, `eager_load` |
| `` `association` requires the associations plugin `` at the first bake outside the suite (`bin/rails runner`, `factory_bakery:doctor`), though a helper requires the plugin | The plugin is enabled only in a spec helper. Boot succeeds — definition blocks run at bake time — and the helper never runs there | Enable it in `config.factory_bakery.associations` ([bad pattern](bad-patterns.md#4-requiring-factory_bakeryassociations-by-hand-in-rails)) |
| `[FactoryBakery] WARN: seed N from a random choice for this process` | No seed source set and no framework integration required | Add `require 'factory_bakery/rspec'` or `'/minitest'`. The line is informational |
| Generated values differ on every run, and `rspec --seed N` does not repeat them | The framework integration is not required, or `FACTORY_BAKERY_SEED` / `FactoryBakery.seed =` outranks it | Require the integration. Check `FactoryBakery.seed` and `ENV['FACTORY_BAKERY_SEED']` |
| `ArgumentError: FACTORY_BAKERY_SEED must be an integer, got "..."` | The variable is not a base-10 integer | Fix the value, or unset it |
| `ArgumentError: FactoryBakery.seed must be an Integer, a callable returning an Integer, or nil` | Wrong type assigned | Assign an Integer or `-> { 1234 }`. `nil` clears it |
| `[FactoryBakery] WARN: left Account#avatar_remote_url blank on purpose` | A `*_remote_url` writer would download the URL, so the gem leaves it blank (once per model and attribute) | Nothing to fix when blank is acceptable. A presence validation on it still fails `bake!`: then set it in a definition or an override. `skip` only silences the WARN (it never fills the value) |

## Quick health check

```sh
RAILS_ENV=test bin/rails runner '
  p version: FactoryBakery::VERSION,
    plugins: FactoryBakery::PluginRegistry.plugins.size,
    paths: FactoryBakery.definition_paths,
    mode: (FactoryBakery::Associations.mode if defined?(FactoryBakery::Associations))
'
```
