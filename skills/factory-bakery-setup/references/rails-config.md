# Rails configuration

Source: `lib/factory_bakery/active_record_mapper/railtie.rb`, `lib/factory_bakery/associations/rail_config.rb`.

## What the Railtie does

At boot, in `config.after_initialize`, in this order:

1. If `config.factory_bakery.associations` is set (not `nil`, not `false`): `require 'factory_bakery/associations'` and configure it.
2. If `config.factory_bakery.fill_optional` is not `nil`: assign it to `FactoryBakery.fill_optional`.
3. Set `FactoryBakery.definition_paths` (from `definition_paths`, or the default directory) and call `FactoryBakery.find_definitions`.

On boot and on every reload (`config.to_prepare`), the polymorphic-target cache is cleared. The Railtie also loads the generators (`generators do`) and the rake tasks (`rake_tasks do`).

## Options

```ruby
# config/application.rb
config.factory_bakery.associations     = { mode: :required_only }
config.factory_bakery.definition_paths = [Rails.root.join('spec/bakery').to_s]
```

| Option | Values | Default |
| --- | --- | --- |
| `associations` | `nil`/`false` (off), `true`, a mode symbol, or a Hash with `mode`, `strategy`, `max_depth`, `default_count`, `eager_load` | unset (off) |
| `fill_optional` | `true`, `false` or an Array of attribute names | unset (core default `false`) |
| `definition_paths` | A String or an Array. Relative paths resolve against `Rails.root` | unset: `spec/bakery` (`test/bakery`) when factory_bot is detected, else the first existing of `spec/factories`, `test/factories`, `factories` |
| `generators` | `true`: the model generator hook always wins. `false`: the hook is off. `nil`: on unless another `fixture_replacement` is selected | unset (`nil`) |

Unknown keys and invalid values raise `ArgumentError`:

- `unknown associations config option :x; expected one of [:mode, :strategy, :max_depth, :default_count, :eager_load]`
- `associations config must be a Hash, true, false or a mode symbol, got ...`
- `invalid associations mode :bogus; expected one of [:none, :required_only, :all]`

## Plugin settings (the Hash keys)

| Key | Default | Values |
| --- | --- | --- |
| `mode` | `:required_only` | `:none`, `:required_only`, `:all` |
| `strategy` | `:fresh` | `:fresh`, `:reuse_non_unique` |
| `max_depth` | `2` | Non-negative Integer |
| `default_count` | `1` | Non-negative Integer |
| `eager_load` | `true` | `true`, `false`. Set `false` in tests that load models themselves, or declare polymorphic targets |

## Core settings (set in an initializer)

```ruby
# config/initializers/factory_bakery.rb
FactoryBakery.configure do |config|
  config.fill_optional  = false   # true, false or an Array of names
  config.max_bake_depth = 10
end
```

An initializer runs **before** the Railtie's `after_initialize`, so these are in place when definitions load.

## Environment placement

| Goal | Where |
| --- | --- |
| All environments the gem is loaded in | `config/application.rb` |
| Tests only | `config/environments/test.rb`, and the gem in `group :test` |

The gem should be in `group :development, :test` or `group :test`. Definitions load at boot wherever the gem is loaded.

## Things to know

- Only one directory is loaded when `definition_paths` is unset (see the table). `definition_paths` itself may list several. Missing directories are skipped.
- Generator behavior, `--skip-factory-bakery`, `--force`, and the rake tasks: [generators-and-rake.md](generators-and-rake.md).
- A definition naming a model (`define(User)`) autoloads it during boot. A bare symbol (`define(:user)`) resolves at the first bake.
- Class-keyed definitions go stale across code reloads. Tests do not reload.
- If `factory_bot` is installed, set `definition_paths` to a separate directory (`bin/rails g factory_bakery:install` does it). Without factory_bot, both gems would default to `spec/factories`. With factory_bot detected, FactoryBakery defaults to `spec/bakery` or `test/bakery`, but state it explicitly.
