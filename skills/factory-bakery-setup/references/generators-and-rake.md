# Generators and rake tasks

<!-- verify against implementation -->

This page documents the **contract** the generators and rake tasks are implemented against. They were being written in parallel to this documentation. Check each command against the installed gem (`bin/rails g --help`, `bin/rails -T factory_bakery`) before relying on the exact output. If a command is missing, create the files by hand.

## Model generator hook

```sh
bin/rails g model Post title:string
```

Also writes a definition stub at `<definitions dir>/post.rb`:

```ruby
FactoryBakery.define(Post) do
end
```

| Control | How |
| --- | --- |
| On by default | Like factory_bot_rails |
| Disable globally | `config.factory_bakery.generators = false` |
| Disable for one run | `--skip-factory-bakery` |
| Replace another gem's `fixture_replacement` | **Not done automatically.** Only if the user opts in |

`<definitions dir>` is the directory FactoryBakery loads: `config.factory_bakery.definition_paths` when set, else the first existing of `spec/factories`, `test/factories`, `factories`.

## Install generator

```sh
bin/rails g factory_bakery:install
```

Creates an initializer and the definitions directory. When `factory_bot` is present it uses `spec/bakery` or `test/bakery` (not `spec/factories` or `test/factories`), so the two gems do not load each other's files. If it picks `spec/bakery`, also set `config.factory_bakery.definition_paths` to that path.

## Definition generator

```sh
bin/rails g factory_bakery:definition Post
```

Writes a stub for one model in the definitions directory.

## Rake tasks

```sh
bin/rails 'factory_bakery:definitions[Post,Comment]'
bin/rails factory_bakery:definitions
bin/rails 'factory_bakery:doctor[Post]'
bin/rails factory_bakery:doctor
WRITE=1 bin/rails factory_bakery:doctor
```

Quote the bracketed form in zsh.

| Task | Behavior |
| --- | --- |
| `factory_bakery:definitions[Post,Comment]` | Writes definition stubs for the named models. With **no arguments**, for every model that has no definition |
| `factory_bakery:doctor[Post]` | Bakes the named model. With no arguments, **every model** |
| `WRITE=1 factory_bakery:doctor` | Also writes stubs for failing models |

`doctor` details:

- For each model it runs `bake` plus `valid?`, then `bake!`.
- Everything is rolled back. Nothing is left in the database.
- It prints each failure with a hint and an anchor into [`diagnostics.md`](../../factory-bakery-diagnostics/references/diagnostics.md).

Run `doctor` in the **test** environment (`RAILS_ENV=test`). It writes rows (rolled back), so never point it at production data.

## Reading doctor output

Take each failure's anchor to the diagnostics catalog. The usual outcomes:

| Anchor family | Usual fix |
| --- | --- |
| `#id-reading-custom-validator` | `association :x, persist: true` |
| `#registry-and-inclusion-lists`, `#time-relative-validations` | One definition line |
| `#cyclic-association` | `skip :edge` or `edge { nil }` |
| `#read-only-target` | `bake` only, or `skip` the edge |
| `#incomplete-persistence` | Persist the named record, or fix `autosave`/`validate` |

Do not write definitions for models that bake fine. A model that passes `doctor` needs no definition.
