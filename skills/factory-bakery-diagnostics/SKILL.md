---
name: factory-bakery-diagnostics
description: >-
  Diagnoses why a model does not bake with FactoryBakery. Use when `FactoryBakery.bake` or `bake!` raises
  (FactoryBakery::Error, IncompletePersistenceError, CyclicAssociationError, ReadOnlyTargetError,
  NestingTooDeepError, an ArgumentError from the association DSL, `Static attributes are unsupported`,
  `Cyclic attribute dependency`), when a baked record is invalid or valid only on some runs (`Chosen at random:`
  in the message), when a value is silently nil or wrong, when a `left X#y_remote_url blank on purpose` WARN
  appears, or when `bin/rails factory_bakery:doctor` lists a failing model. Gives a procedure: reproduce with the
  printed seed, read `FactoryBakery.explain`, classify against the catalog, apply the smallest fix (call-site
  override, one definition line, `persist:`, `with:`, `skip`, or a gem bug report). Not for a first install
  (use factory-bakery-setup) or a move off factory_bot (use factory-bakery-migrate).
---

# Diagnose a FactoryBakery bake failure

Use this when a model does not bake, or bakes into the wrong record. The catalog of every error is [`references/diagnostics.md`](references/diagnostics.md). Its anchors are stable.

## Rules

- Make the **smallest** change that fixes the bake. Ladder: a call-site override, one definition line, `persist:`, `with:`, `skip`, `strategy: :fresh`, then a gem bug report.
- If called from `factory-bakery-migrate`, skip rung 1: no test edits. Start at rung 2 (a definition line).
- Do **not** change a model, its validations or the schema to make baking easier. That is a one-way door: ask the user.
- Reproduce first, with the printed seed. Do not guess, and do not retry until it passes.
- Know which validator or rule each line you add answers, and say so.
- Do not delete or rewrite definitions beyond the failing line.
- Search with the project's code-search tool (`tgrep` when an index exists).
- Before finishing, check the change against [`references/bad-patterns.md`](references/bad-patterns.md).

## Procedure

### 1. Reproduce

**Find the seed.** Every generated value derives from one seed. A `bake!` validation error, `FactoryBakery.explain(record)` and the doctor output for an invalid record all contain a line `Seed N from <source>. Reproduce: <command>`. The startup log line (`[FactoryBakery] INFO: using RSpec seed N ...` or `WARN: seed N from ...`) names it too. Resolution order: `FACTORY_BAKERY_SEED`, then `FactoryBakery.seed =` (Integer or callable), then the test framework's seed (`require 'factory_bakery/rspec'` or `'/minitest'`), then a random seed per process.

The seed covers only what the gem draws (including FFaker, inside a bake). `Faker::`, `rand` and `SecureRandom` in the project's own definition blocks are **not** seeded. Pin them to literals while diagnosing, or a replay can differ for that reason alone.

**Replay it.** Each model's values derive from the seed, the model name and that model's top-level bake ordinal in the process. So the same values need the same seed **and** the same earlier bakes of that model. The error text names the bake (`top-level bake #3 of User in this process`).

1. Start from the original suite command and its test-order seed. A narrower run changes which bakes ran before, and with them the ordinal.
2. Once the failure reproduces, narrow it. Check that the error still says the same `bake #N of Model`.
3. To replay bake #3 of `User` outside the suite, run the two bakes before it, then explain the third. Run it in a transaction that rolls back, because `bake!` commits and plain `bake` can still insert raw-FK parents:

```sh
bundle exec rspec --seed 12345                                 # the original command. Minitest: bin/rails test --seed 12345
FACTORY_BAKERY_SEED=12345 RAILS_ENV=test bin/rails runner 'ActiveRecord::Base.transaction { 2.times { FactoryBakery.bake(User) }; puts FactoryBakery.explain(FactoryBakery.bake(User)); raise ActiveRecord::Rollback }'
```

For a `bake!` failure, replace the last `bake` with `bake!` and read the exception it raises. Database state (rows left by earlier examples) can still differ from the suite, so a clean replay is evidence, not proof. If the runner is valid but the suite fails, replay the suite.

`FactoryBakery.explain(record)` runs `valid?` and returns the invalid attributes, the values FactoryBakery drew (`Chosen at random: ...`), the seed and a definition snippet. For a valid record it returns `<Class> is valid; nothing to explain.` `Chosen at random:` is provenance: it lists a filled attribute the errors name, so it shows where a value came from. It does not prove that value is the cause.

**Doctor** (Rails): `RAILS_ENV=test bin/rails 'factory_bakery:doctor[Model]'` (add `NO_FAIL=1` for exit status `0`). It runs `bake` plus `valid?`, then `bake!`, and rolls the database rows back. Jobs, HTTP calls and file writes that model callbacks make still happen. It prints per failing model the first error line, a hint and a link, then the rest of the error indented (the explanation). It files each failure under one of six anchors, first match wins:

| Doctor links to | Triggered by |
| --- | --- |
| `unique-value-collisions` | `could not generate a unique value` |
| `no-polymorphic-target-discovered` | `no target discovered` |
| `incomplete-persistence` | `IncompletePersistenceError` |
| `db-only-constraints` | `NotNullViolation`, `InvalidForeignKey` |
| `random-value-rejected-by-app-rule` | `Chosen at random:` in the message |
| `domain-rules-inference-cannot-know` | any other error. A catch-all: classify it yourself in step 3 |

Run each model on its own, so one failure does not hide another, and roll back when the database is real. Record four facts: exception class, full message, `bake` / `bake!` / both, and the seed.

### 2. Read the error

| What you see | Do this |
| --- | --- |
| A `FactoryBakery::Error` (or subclass) or an `ArgumentError` naming FactoryBakery concepts | Look the message up in the [index by message](references/diagnostics.md#index-by-message) |
| `Chosen at random:` after a validation error, or a record valid on some seeds only | [random-value-rejected-by-app-rule](references/diagnostics.md#random-value-rejected-by-app-rule) |
| `bake` returns a record that is not valid, or `RecordInvalid` from `bake!` | Read `errors.full_messages` and `explain`. Go to step 3 |
| A database error (`NotNullViolation`, `InvalidForeignKey`, unique violation) | [db-only-constraints](references/diagnostics.md#db-only-constraints) or [has-one-created-by-callback](references/diagnostics.md#has-one-created-by-callback) |
| `Static attributes are unsupported` or `Cyclic attribute dependency` | [factory-attribute-errors](references/diagnostics.md#factory-attribute-errors) |
| A WARN `left X#y_remote_url blank on purpose` | Not an error: the bake succeeded and the WARN records an intentional omission. Still check the bake result. [remote-url-left-blank](references/diagnostics.md#remote-url-left-blank) |
| A subclass bakes with its parent's values | [subclass-uses-parent-definition](references/diagnostics.md#subclass-uses-parent-definition) |
| No error, wrong value | [silent-failures](references/diagnostics.md#silent-failures) |

### 3. Classify

Pick exactly one class.

| Class | Signs | Catalog |
| --- | --- | --- |
| **Definition or DSL mistake** | Unknown trait, unregistered symbol, static or cyclic attribute, `skip` misuse, option errors, plugin not loaded | `unregistered-factory`, `unknown-trait`, `skip-misuse`, `factory-attribute-errors`, `association-plugin-not-loaded`, `association-option-errors` |
| **Association graph** | Cycle, nesting, polymorphic target, missing class, `must exist`, wrong parent reused | `cyclic-association`, `no-polymorphic-target-discovered`, `missing-association-class`, `must-exist-error`, `reuse-picks-owners-own-parent` |
| **Persistence** | `did not persist`, read-only, a validator reading an id, callback-created rows | `incomplete-persistence`, `read-only-target`, `id-reading-custom-validator`, `has-one-created-by-callback` |
| **Value generation** | `could not generate ...` | `unique-value-collisions`, `format-exhaustion`, `numeric-constraint-exhaustion` |
| **A drawn value an app rule rejects** | `Chosen at random:`, valid on some seeds only | `random-value-rejected-by-app-rule`, `registry-and-inclusion-lists` |
| **App rule inference cannot know** | Registry, setting, time rule, structured text, side-effecting setter | `registry-and-inclusion-lists`, `time-relative-validations`, `structured-text-columns`, `side-effecting-writers` |
| **Gem defect** | A declared, discoverable constraint mishandled | Step 5 |
| **Other** | Not above | Use the [index by message](references/diagnostics.md#index-by-message) entry directly |

### 4. Fix with the smallest change

Apply the fix the catalog entry names. In order of preference:

1. **A call-site override** in the test that needs a particular value.
2. **A definition line** when the model needs app knowledge. Name the validator or rule that needs it. Put it in the first entry of `FactoryBakery.definition_paths` (the explanation's "pin it in <file>" line names the exact file, `<underscored class name>.rb` in that directory).
3. **`association :x, persist: true`** when a validator reads a parent's id.
4. **`with: { ... }`** for child attributes on an association.
5. **`skip :x`** for a side-effecting setter (other than a `*_remote_url` writer), a read-only view edge, or a cycle.
6. **`strategy: :fresh`** on an edge where a reused parent breaks a rule.

When an error shows `Chosen at random: provider = "bedrock"`, that value is what was drawn, not the fix. Pick a value the validator accepts. Never paste the snippet's `{ nil }` placeholder as is.

```ruby
# a drawn value an app rule rejects (Discourse LlmModel): pin one the validations accept
FactoryBakery.define(LlmModel) do
  provider { LlmModel::OPEN_AI_PROVIDER_NAME }
end

# a validator reads a parent's id (Discourse TopicLink)
association :topic, persist: true, with: { user: Discourse.system_user }

# a registry value (Discourse AdminDashboardReport)
source { 'core_report' }

# a callback that calls the network (Mastodon AccountAlias#set_uri): alias a local account, no WebFinger request
account { FactoryBakery.bake!(Account) }
acct { FactoryBakery.bake!(Account).username }

# a view as a parent (Mastodon InstanceModerationNote)
skip :instance
domain { 'example.com' }

# a cycle in :all (Mastodon Account)
skip :moved_to_account
```

**`*_remote_url` writers.** The gem never assigns them, because assigning downloads the URL. Each is left blank, with one WARN per model and attribute. The WARN records an intentional omission, so keep checking the bake result: a validator may still need that attribute. When blank is not acceptable, supply a value through a definition or an override (and stub the HTTP call). `skip` only omits the assignment and suppresses the WARN. It does not make an invalid record valid.

A subclass needs no definition when its parent's inherited one bakes it. A subclass definition replaces the inherited one, so repeat the lines it needs.

`name 'x'` (no block) raises `Static attributes are unsupported; use name { "x" }`. Write `name { 'x' }`.

### 5. Or report a gem bug

Only when **all** hold:

1. The failing rule is a declared validator or column constraint, not app logic.
2. A minimal model reproduces it with `FactoryBakery.bake(Model)` alone.
3. A definition line would only be a workaround.

Draft the issue and **show it to the user**. File it only on their approval, with the app's name and its private model names replaced by a minimal generic repro:

```sh
gh issue create -R mohammed-io/factory_bakery --label needs-triage --title '<title>' --body-file <draft>
```

Include `FactoryBakery::VERSION`, the validator, the exact message, the seed and the repro. Meanwhile apply the definition-line workaround with a comment that names the issue once it exists.

### 6. Verify

- `FactoryBakery.bake(Model).valid?` is `true`, and `FactoryBakery.bake!(Model)` succeeds twice in a row (catches uniqueness collisions). Run both inside `ActiveRecord::Base.transaction { ...; raise ActiveRecord::Rollback }`, or use doctor.
- Replay with the original seed **and** with two other seeds (`FACTORY_BAKERY_SEED=1`, `=2`). A fix that holds for one seed only is a coincidence.
- With the associations plugin, if the project uses `:all`: `FactoryBakery::Associations.with(mode: :all) { FactoryBakery.bake(Model) }`.
- Run the affected tests. They must pass exactly as before.
- Rails: `RAILS_ENV=test bin/rails 'factory_bakery:doctor[Model]'` prints `1 valid, 0 needs definition` and exits `0`.

## Fast path

1. Associations plugin loaded? (`FactoryBakery::PluginRegistry.plugins.size`). `must exist` usually means no.
2. Definitions loaded from the right directory? (`FactoryBakery.definition_paths`).
3. Only with `:all`, or only with `:reuse_non_unique`? Reproduce under `Associations.with(...)`.
4. A custom validator reading an `_id`? `persist: true`.
5. The code path touches the network, a registry or "now"? A definition line.
6. Valid on some seeds only? A drawn value fails an app rule: pin it.
7. An STI subclass? It uses its nearest ancestor's definition unless it has its own.

## Bad patterns (top ones)

Full list with before/after code: [`references/bad-patterns.md`](references/bad-patterns.md).

| Do not | Do instead |
| --- | --- |
| Change a validation or the schema so the bake passes | A definition line. Ask first if the model truly must change |
| Re-run until green, or hard-code `FactoryBakery.seed` | Replay with the printed seed, then fix |
| `rescue` the error in the test or a helper | Fix the cause. The error is the diagnosis |
| Add a definition line without knowing which rule needs it | Read `explain`, name the rule, add one line |
| Define every attribute "to be safe" | Only what a test asserts on or the model cannot bake without |
| `skip` an attribute to silence an informational WARN | Leave the WARN. The bake succeeded |
| Diagnose with `Faker::`, `rand` or `SecureRandom` left in the project's blocks | Pin them to literals first. The seed does not cover them |
| A subclass definition that copies the parent's, or forgetting it inherits | Rely on inheritance. Write one only when it must differ, with every line it needs |
| Copy the value `Chosen at random:` printed, or the snippet's `{ nil }` | A value the validator accepts |

## References

| File | Use |
| --- | --- |
| [`references/diagnostics.md`](references/diagnostics.md) | Every error: message, cause, where to look, fix, example |
| [`references/bad-patterns.md`](references/bad-patterns.md) | Diagnosis mistakes with reasons and fixes |

User guide: [`docs/guide/`](../../docs/guide/index.md). First install: [`factory-bakery-setup`](../factory-bakery-setup/SKILL.md). Migration: [`factory-bakery-migrate`](../factory-bakery-migrate/SKILL.md).
