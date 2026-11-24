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
# config/initializers/factory_bakery.rb, inside the generated tap block:
#   Rails.application.config.factory_bakery.tap do |config| ... end
config.definition_paths = [Rails.root.join('spec/bakery').to_s]
```

```ruby
# config/environments/test.rb
config.factory_bakery.associations     = { mode: :required_only }
```

Keep `definition_paths` in the guarded initializer, not only in `test.rb`, so generators and rake tasks read it in the environment they run in (run them with RAILS_ENV=test).

An initializer file has no `config` variable: use `Rails.application.config.factory_bakery.…` — or `config.definition_paths = …` inside the generated `tap` block, where `config` is already the factory_bakery options (`config.factory_bakery.…` there raises `NoMethodError`, and a bare `config.…` at the top level raises `NameError`).

`config.factory_bakery` exists only while the gem is loaded (the Railtie defines it). With the gem in the test groups, `config/application.rb` raises `NoMethodError` at production boot. Use `config/environments/test.rb`, or guard the line: `... if config.respond_to?(:factory_bakery)`.

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
if defined?(FactoryBakery::Railtie)
  FactoryBakery.configure do |config|
    config.fill_optional  = false   # true, false or an Array of names
    config.max_bake_depth = 10
  end
end
```

An initializer runs **before** the Railtie's `after_initialize`, so these are in place when definitions load. The guard is required when the gem is not in the production group: with a `path:`/`git:` source, `FactoryBakery` itself is defined in production, so guard on `FactoryBakery::Railtie` — the guard keeps the file inert in production. The same guard goes around the whole body of the generated initializer, including its `require 'factory_bakery/rspec'` line.

## Environment placement

| Goal | Where |
| --- | --- |
| Tests only (the default) | `config/environments/test.rb`, and the gem in `group :development, :test` or `group :test`. With `group :test` alone, generators and rake tasks need `RAILS_ENV=test` |
| Anywhere the gem is loaded, with the gem in a group that production skips | A guarded line: `config.factory_bakery.associations = ... if config.respond_to?(:factory_bakery)` |
| All environments, with the gem in the default group | `config/application.rb` (not recommended: the gem would be a production dependency) |

Definitions load at boot wherever the gem is loaded.

## Things to know

Common mistakes with these options are in [bad-patterns.md](bad-patterns.md).

- Only one directory is loaded when `definition_paths` is unset (see the table). `definition_paths` itself may list several. Missing directories are skipped.
- Generator behavior, `--skip-factory-bakery`, `--force`, and the rake tasks: [generators-and-rake.md](generators-and-rake.md).
- A definition naming a model (`define(User)`) autoloads it during boot. A bare symbol (`define(:user)`) resolves at the first bake.
- Class-keyed definitions go stale across code reloads. Tests do not reload.
- If `factory_bot` is installed, set `definition_paths` to a separate directory (`RAILS_ENV=test bin/rails g factory_bakery:install` does it). Without factory_bot, both gems would default to `spec/factories`. With factory_bot detected, FactoryBakery defaults to `spec/bakery` or `test/bakery`, but state it explicitly.
