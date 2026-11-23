# Generators and rake tasks

Source: `lib/generators/factory_bakery/**`, `lib/tasks/factory_bakery.rake`, `lib/factory_bakery/active_record_mapper/{railtie,definition_paths,rails_tasks}.rb`. They load with the Railtie, so they exist only in a Rails app that has the gem in the current bundle group. Check with `RAILS_ENV=test bin/rails g --help` and `RAILS_ENV=test bin/rails -T factory_bakery`. If a command is missing, the installed gem predates it — or this environment does not load the gem (group :test only: rerun with `RAILS_ENV=test`). Then create the files by hand.

## Where definitions are written

All generators and `factory_bakery:definitions` write into one directory, `<dir>/<underscored class name>.rb` (`Admin::Post` is `admin/post.rb`):

1. The **first** entry of `config.factory_bakery.definition_paths` when set, read as set in the environment the command runs in. Keep the line in the guarded initializer, so development commands see it too. Relative paths resolve against `Rails.root`.
2. Otherwise the default directory, which is also the one Rails loads at boot:
   - factory_bot detected: `spec/bakery` (`test/bakery` for Minitest). Detected means the `FactoryBot` constant is defined, or a `*.rb` file under `spec/factories`, `test/factories` or `factories` has a line that starts with `FactoryBot.define`.
   - else the first existing of `spec/factories`, `test/factories`, `factories`.
   - else `spec/factories` or `test/factories`. `spec` when the generators' test framework is `:rspec`, or when none is set and `spec/` exists. `test` otherwise.

An existing file is **skipped**. `--force` overwrites it. The stub is:

```ruby
# frozen_string_literal: true

FactoryBakery.define(Post) do
  # title { "MyString" }
  # user { FactoryBakery.bake(User) }
  # subject { FactoryBakery.bake(SomeModel) }   # polymorphic reference
end
```

Attributes given on the command line become commented examples. For a model with no ancestor definition the stub changes nothing until a line is uncommented.

**A stub for a subclass is not inert.** `FactoryBakery.define(Subclass) do ... end` registers an exact definition even when the block holds only comments, and an exact definition replaces the ancestor's (probed: a comment-only `define(Sub)` made `bake(Sub)` lose the parent's attribute and raise `Trait :loud is not declared for Sub`). So do not generate or keep a stub for a subclass that the parent's definition already bakes. Delete the stub, or fill it with every line and trait the subclass needs.

## Model generator hook

```sh
bin/rails g model Post title:string
bin/rails g scaffold Post title:string
```

Both also write the stub. The hook takes Rails' `fixture_replacement` slot, so Rails does not write a fixtures file while it is active.

`config.factory_bakery.generators`:

| Value | Behavior |
| --- | --- |
| unset (`nil`) | On, unless the app already selects another `fixture_replacement` (for example `:factory_bot`). That choice is kept and no FactoryBakery stub is written |
| `true` | On. **Replaces** any other `fixture_replacement` |
| `false` | Off. A `fixture_replacement` of `:factory_bakery` is cleared. Another gem's choice is left alone. Rails writes its fixtures file again |

| Control | How |
| --- | --- |
| Disable for one run | `--skip-factory-bakery` (or `--no-factory-bakery`) |
| Disable globally | `config.factory_bakery.generators = false` |
| Replace another gem's `fixture_replacement` | `config.factory_bakery.generators = true`. **Ask the user first.** The default never does it |

The hook is wired when generators load and needs a test framework in `config.generators`.

## Install generator

```sh
RAILS_ENV=test bin/rails g factory_bakery:install
```

Creates `config/initializers/factory_bakery.rb` (an existing one is skipped, `--force` overwrites) and the definitions directory.

- The initializer sets `Rails.application.config.factory_bakery` and lists `associations`, `definition_paths`, `fill_optional`, `generators` as commented examples. Nothing is on until a line is uncommented.
- **The generated file is unguarded.** In production, with the gem installed there, it loads FactoryBakery and its definitions into the process; with `BUNDLE_WITHOUT=test` its top-level `require 'factory_bakery/rspec'` raises `LoadError: cannot load such file -- factory_bakery/rspec`; with no framework require written, `Rails.application.config.factory_bakery` raises `NoMethodError: undefined method 'factory_bakery'`. Wrap the whole file body in `if defined?(FactoryBakery::Railtie) ... end` (check: `lib/generators/factory_bakery/install/templates/initializer.rb.tt` has no guard).
- It also writes `require 'factory_bakery/rspec'` when `spec/` exists, else `require 'factory_bakery/minitest'` when `test/` exists, so generated values follow the framework's seed. With neither directory it writes no require.
- **factory_bot detected** (same test as above): creates `spec/bakery` (`test/bakery`) and writes an active `config.definition_paths = ["spec/bakery"]`. The two gems then never load each other's files.
- **Otherwise**: creates the directory Rails would load (first `definition_paths` entry, else the default above) and leaves `definition_paths` commented.

The initializer does not turn the associations plugin on. Uncomment `config.associations = :required_only` inside the guarded initializer, or set it in `config/environments/test.rb`, if the app needs it. Not in `config/application.rb` unless the line carries `if config.respond_to?(:factory_bakery)`.

## Definition generator

```sh
RAILS_ENV=test bin/rails g factory_bakery:definition Post
RAILS_ENV=test bin/rails g factory_bakery:definition Admin::Post title:string user:references
```

Writes one stub in the directory above. Existing file: skipped, `--force` overwrites.

## Rake tasks

```sh
RAILS_ENV=test bin/rails 'factory_bakery:definitions[Post,Comment]'
RAILS_ENV=test bin/rails factory_bakery:definitions
RAILS_ENV=test bin/rails 'factory_bakery:doctor[Post,Admin::Post]'
RAILS_ENV=test bin/rails factory_bakery:doctor
RAILS_ENV=test WRITE=1 NO_FAIL=1 bin/rails factory_bakery:doctor
```

Quote the bracketed form in zsh. Arguments are Active Record class names, comma separated. A name that is not a concrete Active Record model aborts the task: `Unknown concrete Active Record model: <name>`. With no names, both tasks eager-load the app and cover every concrete model (abstract classes are skipped).

| Task | Behavior |
| --- | --- |
| `factory_bakery:definitions[Post,Comment]` | Writes a stub for each named model, same output as the definition generator |
| `factory_bakery:definitions` | Writes stubs for every concrete model that has **no registered class-keyed definition** |
| `factory_bakery:doctor[Post]` | Checks the named models |
| `factory_bakery:doctor` | Checks **every** concrete model |

`doctor` details:

- Per model: `bake` plus `valid?` first, then `bake!`, which must persist the record. The first error found is kept (validation before persistence).
- Each probe, and the whole run, is rolled back on every Active Record connection pool registered for the current role. Rows already in the database are untouched. Model callbacks still run, so a job, an HTTP call or a file write they make is **not** rolled back.
- Each failure prints one line: `Model: <first line of the error> — <hint> (<link>)`. The link is `https://github.com/mohammed-io/factory_bakery/blob/main/docs/diagnostics.md#<anchor>`. The rest of the error follows, indented by two spaces. For an invalid record that includes the explanation: the invalid attributes, `Chosen at random: ...`, the seed with its reproduce command, and a definition snippet (same text as `FactoryBakery.explain(record)`).
- The last line is `N valid, M needs definition`.

| Control | Effect |
| --- | --- |
| exit status | `1` when any model fails, `0` when all pass |
| `NO_FAIL=1` | Exit `0` even when models fail (report only) |
| `WRITE=1` | Also write a stub for each failing model, with the error as `#` comment lines at the top. An existing file is kept |

Run `doctor` in the **test** environment (`RAILS_ENV=test`, on every command). It writes rows (rolled back) and runs model callbacks, so never point it at real data.

## Reading doctor output

Doctor emits only these six anchors (published at `docs/diagnostics.md`, same text as the [catalog](../../factory-bakery-diagnostics/references/diagnostics.md)). The first pattern that matches the message wins, in this order:

| Anchor | Triggered by | Usual fix |
| --- | --- | --- |
| `#unique-value-collisions` | `could not generate a unique value` | A definition line that varies per bake, or widen the rule |
| `#no-polymorphic-target-discovered` | `no target discovered` | `association :x, SomeClass`, or `skip :x` |
| `#incomplete-persistence` | `IncompletePersistenceError` | Persist the named record, or fix `autosave`/`validate` |
| `#db-only-constraints` | `NotNullViolation`, `InvalidForeignKey` | A definition line giving a value the database accepts |
| `#random-value-rejected-by-app-rule` | `Chosen at random:` in the message | Pin the value in a definition, using one your validations accept |
| `#domain-rules-inference-cannot-know` | Any other error | Catch-all. Read the message and classify it with the diagnostics skill |

A `domain-rules-inference-cannot-know` link does not mean the error is a domain rule. Other kinds (`#cyclic-association`, `#read-only-target`, `#id-reading-custom-validator`) land there too. Use the printed message and the catalog's [index by message](../../factory-bakery-diagnostics/references/diagnostics.md#index-by-message).

Do not write definitions for models that bake fine. A model that passes `doctor` needs no definition ([bad pattern](bad-patterns.md#13-generating-stubs-for-every-model)).
