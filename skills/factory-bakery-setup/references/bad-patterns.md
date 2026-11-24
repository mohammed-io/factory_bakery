# Setup bad patterns

Each entry: the pattern, why it hurts, what to do instead. Every claim is checked against `lib/` or `docs/guide/`. One entry is general Rails knowledge and is marked as not run here.

Contents: [gem group](#1-the-gem-in-the-default-or-production-group) · [shared directory](#2-factorybakery-and-factory_bot-loading-one-directory) · [global `:all`](#3-all-mode-set-globally) · [manual associations require](#4-requiring-factory_bakeryassociations-by-hand-in-rails) · [no seed integration](#5-no-seed-integration-require) · [hard-coded seed](#6-a-hard-coded-seed-in-ci) · [reset_plugins!](#7-factorybakeryreset_plugins-in-an-app-suite) · [definitions in app/](#8-definitions-inside-app-or-an-autoload-path) · [generators = true](#9-generators--true-next-to-factory_bot) · [global defaults](#10-defining-on-object-or-applicationrecord-for-a-global-default) · [bake at load time](#11-baking-at-file-load) · [find_definitions per example](#12-calling-find_definitions-per-example) · [stub flood](#13-generating-stubs-for-every-model) · [doctor outside test](#14-running-doctor-outside-the-test-environment) · [unguarded config](#15-factorybakery-config-or-requires-where-the-gem-is-not-loaded)

## 1. The gem in the default or production group

**Why it hurts.** The Railtie loads every definition file at boot in every environment where the gem is loaded ([rails.md](../../../docs/guide/rails.md#things-to-know)). A production boot then evaluates test definitions, and `factory_bakery` becomes a production dependency.

```ruby
# bad
gem 'factory_bakery', path: '/absolute/path/to/factory_bakery'

# good
group :development, :test do
  gem 'factory_bakery', path: '/absolute/path/to/factory_bakery'
end
```

## 2. FactoryBakery and factory_bot loading one directory

**Why it hurts.** Each library evaluates the other's files: factory_bot files can be loaded twice and raise duplicate-definition errors, and either library can fail at boot on files written for the other (the catalog lists `NoMethodError` or a duplicate-definition error, [definition-load-errors](../../factory-bakery-diagnostics/references/diagnostics.md#definition-load-errors)). FactoryBakery defaults to `spec/bakery` or `test/bakery` when it detects factory_bot, but detection can miss (the `FactoryBot` constant is not defined yet and no file starts a line with `FactoryBot.define`).

**Instead.** State a separate directory.

```ruby
# bad: both libraries read spec/factories
# good: config/initializers/factory_bakery.rb, inside the generated tap block
config.definition_paths = [Rails.root.join('spec/bakery').to_s]
```

`RAILS_ENV=test bin/rails g factory_bakery:install` writes this line when it detects factory_bot: the generator writes a relative path such as `["spec/bakery"]` or `["test/bakery"]`, only into a new initializer (an existing file is kept); the absolute form above is equivalent.

## 3. `:all` mode set globally

**Why it hurts.** `:all` builds every non-polymorphic `belongs_to` (optional ones too), every `has_one` and `default_count` rows for every `has_many`, to `max_depth`. That is more rows, slower bakes, more cycles to break with `skip`, and optional children that are invalid are silently dropped, so the graph differs between models without an error ([associations.md](../../../docs/guide/associations.md#all-stays-bounded)). A test that reads an optional edge should say so.

```ruby
# bad
config.factory_bakery.associations = { mode: :all }

# good: global default stays required-only
config.factory_bakery.associations = { mode: :required_only }

# good: the one test that needs the optional graph
FactoryBakery::Associations.with(mode: :all, default_count: 3) { bake!(Post) }
```

## 4. Requiring `factory_bakery/associations` by hand in Rails

**Why it hurts.** The Railtie already requires and configures the plugin when `config.factory_bakery.associations` is set, before definitions load. A second `require` in `spec/rails_helper.rb` is harmless (registration is idempotent) but it hides where the mode is set. And if it is the **only** place that enables the plugin, it runs after `config/environment`. Boot still succeeds — definition blocks run at bake time — but the first bake outside the suite (`bin/rails runner`, `factory_bakery:doctor`) raises `` `association` requires the associations plugin ``: those never run the helper, so they see no plugin and report `must exist` failures the suite does not have.

```ruby
# bad: spec/rails_helper.rb
require 'factory_bakery/associations'

# good: config/environments/test.rb (see bad pattern 15 for config/application.rb)
config.factory_bakery.associations = { mode: :required_only }
```

Outside Rails the `require` is the right switch.

## 5. No seed integration require

**Why it hurts.** Without `require 'factory_bakery/rspec'` (or `'/minitest'`) the seed is random per process, logged at WARN, and `rspec --seed N` does not reproduce generated values. A failure that depends on a value cannot be replayed. `srand` no longer helps either: the gem does not draw from Ruby's global RNG.

```ruby
# bad: spec/rails_helper.rb has only the include
RSpec.configure { |config| config.include FactoryBakery::Methods }

# good
require 'factory_bakery/rspec'
RSpec.configure { |config| config.include FactoryBakery::Methods }
```

`RAILS_ENV=test bin/rails g factory_bakery:install` writes the require into the initializer. Keep one framework require: the seed has a single framework slot and the last require wins.

## 6. A hard-coded seed in CI

**Why it hurts.** The same seed gives the same values for the same models and bake order, every run. Value-shape bugs and hidden dependence on a fixed value never surface in CI.

```ruby
# bad: values never vary
FactoryBakery.seed = 1234

# good: leave it unset. To replay one failing run, from the shell:
#   FACTORY_BAKERY_SEED=1234 bundle exec rspec spec/models/user_spec.rb
```

`FACTORY_BAKERY_SEED` outranks `FactoryBakery.seed =` and the framework seed, so a run can be pinned without a code change. Reproducing also needs the same earlier bakes ([Randomness](../../../docs/guide/configuration.md#randomness)).

## 7. `FactoryBakery.reset_plugins!` in an app suite

**Why it hurts.** It removes every plugin, including the associations plugin the Railtie registered once at boot. Later examples then raise on `association` and stop building required parents (`must exist`).

`FactoryBakery::Associations.reset_configuration!` is no substitute in an app suite. It resets the plugin to **the gem's defaults** (`mode: :required_only`, `strategy: :fresh`, `max_depth: 2`, ...), not to what `config.factory_bakery.associations` set, so after the first example the app's config is gone.

```ruby
# bad
config.after { FactoryBakery.reset_plugins! }
config.after { FactoryBakery::Associations.reset_configuration! }

# good: call nothing. For a change in one test, a scope that restores itself
FactoryBakery::Associations.with(mode: :all) { bake!(Post) }
```

Call `reset_configuration!` only in specs that assign the plugin's globals themselves (`FactoryBakery::Associations.mode = ...`) and want the gem's defaults back. Reset plugins only in specs of your own that register a plugin and register it again.

## 8. Definitions inside `app/` or an autoload path

**Why it hurts.** FactoryBakery loads definition files itself, with `Kernel.load`, from `definition_paths`. Nothing needs them autoloadable. Under Zeitwerk each file in an autoload path must define a constant named after the file, and a definition file defines none, so eager loading (production, CI) raises `Zeitwerk::NameError`. That Zeitwerk behavior is general Rails knowledge and was not run here. Also, the gem is not loaded in production, so `FactoryBakery.define` is not available there (with a `path:`/`git:` source only the bare `FactoryBakery` module exists, holding `VERSION`: the gemspec requires `lib/factory_bakery/version`).

```text
# bad:  app/factories/user.rb
# good: spec/factories/user.rb   (or spec/bakery/user.rb next to factory_bot)
```

## 9. `generators = true` next to factory_bot

**Why it hurts.** `true` always selects FactoryBakery for `fixture_replacement`, replacing factory_bot's generator hook. `bin/rails g model` stops writing factory_bot factories without a message. Unset (the default) keeps another gem's choice.

```ruby
# bad (in a factory_bot app)
config.factory_bakery.generators = true

# good: leave it unset, and write stubs on demand
#   RAILS_ENV=test bin/rails g factory_bakery:definition Post
```

Ask the user before setting `true`. See [generators-and-rake.md](generators-and-rake.md#model-generator-hook).

## 10. Defining on `Object` or `ApplicationRecord` for a global default

**Why it hurts.**

- `FactoryBakery.define(Object)` never applies to another class: `Object` and `BasicObject` are never inherited from.
- A definition on `ApplicationRecord` (or `ActiveRecord::Base`) **is** inherited, by every model with no definition of its own or of a closer ancestor. Its lines go to models that have no such attribute, and a missing setter is skipped silently, so mistakes stay invisible.
- An exact definition replaces the inherited one (definitions do not merge), so each model's own definition must repeat the shared lines.

**Instead.** One definition per model. A real STI or inheritance base is the intended use of inheritance. To share lines, share a block:

```ruby
common = proc { created_by { 'tests' } }
FactoryBakery.define(Post, &common)
FactoryBakery.define(Comment, &common)
```

## 11. Baking at file load

**Why it hurts.** A bake outside an example runs before transactional tests start, so its rows outlive the example and the data leaks between examples ([testing-recipes.md](../../../docs/guide/testing-recipes.md#data-per-example)).

```ruby
# bad
POST = FactoryBakery.bake!(Post)

# good
let(:post) { bake!(Post) }
```

## 12. Calling `find_definitions` per example

**Why it hurts.** Rails already calls it once at boot. `find_definitions` runs `Kernel.load` on every file again, so each call re-evaluates the definitions, resets file-level counters and costs time.

```ruby
# bad
before { FactoryBakery.find_definitions }

# good: nothing. Rails loaded them at boot. Outside Rails, call it once in the helper.
```

## 13. Generating stubs for every model

**Why it hurts.** `bin/rails factory_bakery:definitions` with no names writes a file for every concrete model without a class-keyed definition, and it eager-loads the app. The stubs are comments, so they are inert for a model with no ancestor definition — a subclass stub is not (see below) — but they bury the few definitions that matter. A model that passes `doctor` needs no definition.

**Instead.** Run `RAILS_ENV=test NO_FAIL=1 bin/rails factory_bakery:doctor`, then write stubs only for the failing models (`RAILS_ENV=test bin/rails 'factory_bakery:definitions[Post,Comment]'`, or `WRITE=1`) and fill each with the one line its failure needs.

A stub for a **subclass** is worse than clutter. `FactoryBakery.define(Subclass) do ... end` registers an exact definition even when the block holds only comments, and it replaces the ancestor's definition. The subclass then loses the parent's attributes and traits (probed: `bake(Sub)` returned a `nil` name and `bake(Sub, :loud)` raised `Trait :loud is not declared for Sub`). Delete such a stub, or fill it with every line and trait the subclass needs.

## 14. Running doctor outside the test environment

**Why it hurts.** Doctor writes rows and rolls them back, but model callbacks still run, so a job, an HTTP call or a file write they make is not rolled back. Pointing it at real data is unsafe.

```sh
# bad
bin/rails factory_bakery:doctor
# good
RAILS_ENV=test NO_FAIL=1 bin/rails factory_bakery:doctor
```

## 15. FactoryBakery config or requires where the gem is not loaded

**Why it hurts.** `config.factory_bakery` exists only while the gem is loaded: the Railtie defines it. With the gem in `group :development, :test`, production never loads it, so `config.factory_bakery.associations = ...` in `config/application.rb` raises `NoMethodError: undefined method 'factory_bakery'` at production boot (probed). The generated `config/initializers/factory_bakery.rb` spans the three production cases: with the gem installed in production it loads FactoryBakery and its definitions into the process; with every group that lists the gem excluded (`BUNDLE_WITHOUT=development:test`, or `=test` when the gem is in `group :test` only) its top-level `require 'factory_bakery/rspec'` raises `LoadError: cannot load such file -- factory_bakery/rspec`; with no framework require written, `Rails.application.config.factory_bakery` raises the `NoMethodError`. The `defined?(FactoryBakery::Railtie)` guard covers the **second and third** outcomes only; the first is prevented by the group rule (bad pattern 1), not by the guard.

```ruby
# bad: config/application.rb
config.factory_bakery.associations = { mode: :required_only }

# good: config/environments/test.rb
config.factory_bakery.associations = { mode: :required_only }

# also good where the line must stay in application.rb
config.factory_bakery.associations = { mode: :required_only } if config.respond_to?(:factory_bakery)
```

```ruby
# good: config/initializers/factory_bakery.rb, whole body guarded
if defined?(FactoryBakery::Railtie)
  require 'factory_bakery/rspec'
  Rails.application.config.factory_bakery.tap do |config|
    # ...
  end
end
```
