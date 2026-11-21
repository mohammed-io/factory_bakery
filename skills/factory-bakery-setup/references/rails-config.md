# Rails configuration

Source: `lib/factory_bakery/active_record_mapper/railtie.rb`, `lib/factory_bakery/associations/rail_config.rb`.

## What the Railtie does

At boot, in `config.after_initialize`, in this order:

1. If `config.factory_bakery.associations` is set (not `nil`, not `false`): `require 'factory_bakery/associations'` and configure it.
2. Set `FactoryBakery.definition_paths` and call `FactoryBakery.find_definitions`.

On boot and on every reload (`config.to_prepare`), the polymorphic-target cache is cleared.

## Options

```ruby
# config/application.rb
config.factory_bakery.associations     = { mode: :required_only }
config.factory_bakery.definition_paths = [Rails.root.join('spec/bakery').to_s]
```

| Option | Values | Default |
| --- | --- | --- |
| `associations` | `nil`/`false` (off), `true`, a mode symbol, or a Hash with `mode`, `strategy`, `max_depth`, `default_count`, `eager_load` | unset (off) |
| `definition_paths` | A String or an Array of absolute paths | unset: the first existing of `spec/factories`, `test/factories`, `factories` |
| `generators` | `false` disables the model generator hook <!-- verify against implementation --> | `true` |

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

- Only the first existing conventional directory is loaded.
- A definition naming a model (`define(User)`) autoloads it during boot. A bare symbol (`define(:user)`) resolves at the first bake.
- Class-keyed definitions go stale across code reloads. Tests do not reload.
- If `factory_bot` is installed, set `definition_paths` to a separate directory. Both gems default to `spec/factories`.
