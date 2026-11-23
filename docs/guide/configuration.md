# Configuration

Every setting, with its default and how to change it. FactoryBakery has no config file. Settings are Ruby calls, process-wide unless stated.

## Core

| Setting | Default | Set with | Notes |
| --- | --- | --- | --- |
| `fill_optional` | `false` | `FactoryBakery.fill_optional = true`, `FactoryBakery.configure { \|c\| c.fill_optional = ... }`, or `bake(X, fill_optional: ...)` | `true`, `false`, or an Array of names. `nil` is treated as `false`. Invalid values raise `ArgumentError`. See [Heuristics](heuristics.md#fill_optional) |
| `validate` | `true` | `FactoryBakery.validate = false`, `FactoryBakery.configure { \|c\| c.validate = false }`, or `bake(X, validate: false)` | `true` or `false`; `nil` is treated as `true`, anything else raises `ArgumentError`. Off: the gem runs none of its own checks (the verified fallback's `valid?` probe and rebuild, the verification of optional fills, and the build-time uniqueness checks), so a record may come back invalid, like `FactoryBot.build`. `bake!` still validates on save. See [Heuristics](heuristics.md#the-verified-fallback) |
| `savepoints` | `false` | `FactoryBakery.savepoints = true`, `FactoryBakery.configure { \|c\| c.savepoints = true }`, or `config.factory_bakery.savepoints = true` in Rails | Off: the gem opens no transaction of its own, like factory_bot, so a failed `bake!` leaves the rows `save!` already wrote and a discarded fallback attempt leaves the rows it wrote (a transactional test cleans them up). On: `bake!` runs in a savepoint and rolls back whole, and the fallback's lean attempt is rolled back so the rebuild leaves one copy. The associations plugin's best-effort edges keep their savepoints either way. See [`bake` vs `bake!`](bake-vs-bake-bang.md#savepoints) |
| `max_bake_depth` | `10` | `FactoryBakery.max_bake_depth = n` | Nested bakes past this raise `NestingTooDeepError` |
| `definition_paths` | `[]` | `FactoryBakery.definition_paths = [...]` | A String or an Array. Rails sets it for you. See [Definitions](definitions.md#loading-definition-files) |

`FactoryBakery.configure` yields `FactoryBakery` itself, so any writer works inside it:

```ruby
FactoryBakery.configure do |config|
  config.fill_optional = false
  config.max_bake_depth = 15
  config.definition_paths = ['spec/bakery']
end
```

Per-call `fill_optional:` beats the global value. A nested bake inherits the caller's choice, except inside the verified fallback's rebuild (see [Heuristics](heuristics.md#the-verified-fallback)).

## Associations plugin

Available after `require 'factory_bakery/associations'`.

| Setting | Default | Values |
| --- | --- | --- |
| `Associations.mode` | `:required_only` | `:none`, `:required_only`, `:all` |
| `Associations.strategy` | `:fresh` | `:fresh`, `:reuse_non_unique` |
| `Associations.max_depth` | `2` | Non-negative Integer |
| `Associations.default_count` | `1` | Non-negative Integer |
| `Associations.eager_load` | `true` | `true`, `false` |

Errors raised for bad values:

```
invalid associations mode :bogus; expected one of [:none, :required_only, :all]
invalid associations strategy :reuse; expected one of [:fresh, :reuse_non_unique]
max_depth must be a non-negative Integer, got -1
eager_load must be true or false, got "yes"
```

Scope a change to one block (fiber-local, nests, restores on error):

```ruby
FactoryBakery::Associations.with(mode: :all, max_depth: 3) { FactoryBakery.bake!(Post) }
```

Restore defaults in tests: `FactoryBakery::Associations.reset_configuration!`. Details: [Associations](associations.md#settings-and-scoping).

## Rails

| Setting | Default | Notes |
| --- | --- | --- |
| `config.factory_bakery.associations` | unset (core only) | `true`, a mode symbol, or a Hash of the plugin settings |
| `config.factory_bakery.fill_optional` | unset (core default, `false`) | `true`, `false` or an Array of attribute names. Assigned to `FactoryBakery.fill_optional` at boot |
| `config.factory_bakery.validate` | unset (core default, `true`) | `true` or `false`. Assigned to `FactoryBakery.validate` at boot |
| `config.factory_bakery.savepoints` | unset (core default, `false`) | `true` or `false`. Assigned to `FactoryBakery.savepoints` at boot |
| `config.factory_bakery.definition_paths` | unset (`spec/bakery` or `test/bakery` when factory_bot is detected, else the first existing of `spec/factories`, `test/factories`, `factories`) | A String or an Array. Relative paths resolve against `Rails.root` |
| `config.factory_bakery.generators` | unset (the model-generator hook is on unless another `fixture_replacement` is selected) | `true` always selects FactoryBakery. `false` turns the hook off. See [Rails](rails.md#model-generator-hook) |

Details and generators: [Rails](rails.md).

## Isolation helpers for tests

| Call | Effect |
| --- | --- |
| `FactoryBakery.reset_plugins!` | Removes every plugin (associations and attachments included) |
| `FactoryBakery.reset_cache!` | Drops every per-model-class fact the gem cached (columns, constraints, fillers, ...). Rails does this for you on code reload and on `reset_column_information`; call it yourself if you change a schema or a model's validations behind the gem's back |
| `FactoryBakery::Associations.reset_configuration!` | Restores plugin defaults and clears this fiber's scope |
| `FactoryBakery::FillOptional.reset!` | Restores `fill_optional` and clears the fiber scope. Internal, but handy in a spec of your own |

Do not call `reset_plugins!` between examples of an app suite unless you register the plugins again. The Railtie registers the associations plugin once, at boot.

## Environment

| Variable | Used by |
| --- | --- |
| `WRITE=1` | `bin/rails factory_bakery:doctor`: also writes a stub definition for each failing model |
| `NO_FAIL=1` | `bin/rails factory_bakery:doctor`: exits `0` even when models fail (the default exit status is `1`) |
| `FACTORY_BAKERY_SEED=1234` | The seed for generated values. Takes precedence over `FactoryBakery.seed =` and the test framework. See [Randomness](#randomness) |
| `SKIP_REGEX_COVERAGE_GATE=1` | The gem's own spec run on a single file. Not for apps |

## Randomness

Every generated value derives from one seed. The gem resolves it on first use, and the first source that answers wins:

| # | Source | How to set it | Announced at |
| --- | --- | --- | --- |
| 1 | Environment | `FACTORY_BAKERY_SEED=1234` | WARN |
| 2 | Setting | `FactoryBakery.seed = 1234`, or `FactoryBakery.seed = -> { MyCI.build_number }` (a callable, called once when the seed is resolved; it must return an Integer, else `ArgumentError`) | WARN |
| 3 | Test framework | `require 'factory_bakery/rspec'` (RSpec's seed) or `require 'factory_bakery/minitest'` (Minitest's seed) | INFO |
| 4 | Random | Nothing set: one random seed for the process | WARN |

The environment variable outranks `FactoryBakery.seed =` on purpose, so CI can pin a seed without a code change. A callable is not called when you assign it, only when the seed is resolved. A callable outranks the test framework's seed, so `FactoryBakery.seed = -> { ... }` takes over from `rspec --seed`. Assigning `seed` again, or registering the framework source, resolves the seed again.

`FactoryBakery.seed` returns the resolved Integer in use, resolving it first if needed. Assigning anything other than an Integer, a callable or `nil` raises `ArgumentError`.

Each resolution is announced once through `FactoryBakery.logger` (stderr by default; set it to `nil` to silence). A callable is named `FactoryBakery.seed= (callable)`:

```
[FactoryBakery] INFO: using RSpec seed 12345 for generated data (rspec --seed 12345 reproduces it)
[FactoryBakery] WARN: seed 1234 from FACTORY_BAKERY_SEED (not the test framework's seed); reproduce with FACTORY_BAKERY_SEED=1234
[FactoryBakery] WARN: seed 99 from FactoryBakery.seed= (callable) (not the test framework's seed); reproduce with FACTORY_BAKERY_SEED=99
```

How the seed becomes values:

- Each top-level bake (`bake` or `bake!`) draws from its own generator, derived from the seed, the model's class name, and how many top-level bakes of that class ran earlier in this process. The same seed, model and order of bakes gives the same values. One model's values do not depend on which other models were baked before it.
- Nested bakes, made by declaration blocks, share their top-level bake's generator.
- FFaker, which the gem uses for strings, is seeded per top-level bake and restored afterwards.
- Relative dates (`created_at` a few days ago, `expires_at` in the future) are computed from the clock, so they move from day to day even with a fixed seed.
- Reproducing a failing record needs its seed and the same earlier bakes. Running one spec file can change the count. The invalid-record message names the bake number it came from.

When a bake produces a record that is invalid, see [Random value rejected by an app rule](../../skills/factory-bakery-diagnostics/references/diagnostics.md#random-value-rejected-by-app-rule) and `FactoryBakery.explain(record)`.
