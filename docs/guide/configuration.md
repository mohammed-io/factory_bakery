# Configuration

Every setting, with its default and how to change it. FactoryBakery has no config file. Settings are Ruby calls, process-wide unless stated.

## Core

| Setting | Default | Set with | Notes |
| --- | --- | --- | --- |
| `fill_optional` | `false` | `FactoryBakery.fill_optional = true`, `FactoryBakery.configure { \|c\| c.fill_optional = ... }`, or `bake(X, fill_optional: ...)` | `true`, `false`, or an Array of names. `nil` is treated as `false`. Invalid values raise `ArgumentError`. See [Heuristics](heuristics.md#fill_optional) |
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
| `config.factory_bakery.definition_paths` | unset (first existing of `spec/factories`, `test/factories`, `factories`) | A String or an Array of absolute paths |
| `config.factory_bakery.generators` | `true` <!-- verify against implementation --> | `false` disables the model-generator hook |

Details and generators: [Rails](rails.md).

## Isolation helpers for tests

| Call | Effect |
| --- | --- |
| `FactoryBakery.reset_plugins!` | Removes every plugin (associations and attachments included) |
| `FactoryBakery::Associations.reset_configuration!` | Restores plugin defaults and clears this fiber's scope |
| `FactoryBakery::FillOptional.reset!` | Restores `fill_optional` and clears the fiber scope. Internal, but handy in a spec of your own |

Do not call `reset_plugins!` between examples of an app suite unless you register the plugins again. The Railtie registers the associations plugin once, at boot.

## Environment

| Variable | Used by |
| --- | --- |
| `WRITE=1` | `bin/rails factory_bakery:doctor`, to write stubs for failing models <!-- verify against implementation --> |
| `SKIP_REGEX_COVERAGE_GATE=1` | The gem's own spec run on a single file. Not for apps |

## Randomness

FactoryBakery uses Ruby's global RNG (through FFaker for strings). `srand(seed)` makes a run repeatable. Call it yourself in a `before(:suite)` hook if you want baked values to follow a seed you print.
