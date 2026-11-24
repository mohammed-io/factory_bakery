# FactoryBakery guide

FactoryBakery builds test objects from your model's own metadata. Validators and column types decide what each attribute gets. A definition is a thin layer for the few values a test really cares about.

This guide covers the gem as of `v0.0.2` (branch `mohd/v0.0.2`). The code is the source of truth. If this guide and the code disagree, the code wins. Please open an issue.

## Read in this order

| # | Page | You learn |
| --- | --- | --- |
| 1 | [Getting started](getting-started.md) | Install, first `bake`, first definition |
| 2 | [`bake` vs `bake!`](bake-vs-bake-bang.md) | What gets saved, the transaction, what is verified |
| 3 | [Definitions](definitions.md) | `define`, attribute blocks, `skip`, `initialize_with`, named factories, loading files |
| 4 | [Traits](traits.md) | Reusable overrides on top of a definition |
| 5 | [Overrides and precedence](overrides-and-precedence.md) | Which value wins, and why |
| 6 | [Heuristics](heuristics.md) | What is inferred from which validator or column, `fill_optional`, the verified fallback |
| 7 | [Associations](associations.md) | The opt-in plugin, modes, strategies, the `association` DSL |
| 8 | [Attachments](attachments.md) | Active Storage and Paperclip |
| 9 | [Plugins](plugins.md) | How plugins work, and how to write one |
| 10 | [Sequel and ActiveModel](sequel-and-activemodel.md) | Non-ActiveRecord targets |
| 11 | [Configuration](configuration.md) | Every setting in one place |
| 12 | [Rails](rails.md) | Railtie, `config.factory_bakery.*`, generators, rake tasks |
| 13 | [Testing recipes](testing-recipes.md) | RSpec, Minitest, data per example, speed |
| 14 | [FAQ](faq.md) | Short answers to common surprises |
| 15 | [Types (Sorbet)](types.md) | `bake(User)` is typed as `User`; what is and is not checked |

## Coming from another tool

- [Migrating from factory_bot](migrating-from-factory-bot.md). Also covers fabrication, machinist, Rails fixtures and hand-rolled `create!` helpers.

## Reference

- Diagnosing a failing bake: [`skills/factory-bakery-diagnostics/references/diagnostics.md`](../../skills/factory-bakery-diagnostics/references/diagnostics.md). Every error kind, with cause and fix.
- Agent skills (setup, migration, diagnostics): [`skills/`](../../skills/).
- Design decisions: [`docs/adr/`](../adr/).

## Glossary

The project glossary lives in [`GLOSSARY.md`](../../GLOSSARY.md) at the repo root. It defines *discoverable constraint*, *app-specific setup* and *attribute omission*. The rest of this guide uses these words as they are defined there.

## Conventions used in this guide

- `bake(X)` means `FactoryBakery.bake(X)`. Inside a test that includes `FactoryBakery::Methods` you can write it bare.
- Error messages are quoted from `lib/`. `X`, `Y` stand for your class and association names.
- A sentence that says "not verified" marks a claim the author read in the code but did not run.
