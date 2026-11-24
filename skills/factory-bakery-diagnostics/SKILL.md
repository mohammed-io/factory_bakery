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
  override, one definition line, `persist:`, `with:`, `skip`, `strategy: :fresh`, or a gem bug report). Not for a first install
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

**Find the seed.** Every generated value derives from one seed. A `bake!` validation error, `FactoryBakery.explain(record)` and the doctor output for an invalid record all contain a line `Seed N from <source>. Reproduce: <command>`. The seed log line names it too: the seed resolves on first use, so the line prints at the first bake unless code read `FactoryBakery.seed` earlier (`[FactoryBakery] INFO: using RSpec seed N ...` or `WARN: seed N from ...`). Resolution order: `FACTORY_BAKERY_SEED`, then `FactoryBakery.seed =` (Integer or callable), then the test framework's seed (`require 'factory_bakery/rspec'` or `'/minitest'`), then a random seed per process.

The seed covers only what the gem draws: FFaker inside a bake is seeded, including in your own blocks. `Faker::`, `Kernel.rand` and `SecureRandom` in the project's blocks are **not** seeded. Pin them to literals while diagnosing, or a replay can differ for that reason alone.

**Replay it.** Values derive from the seed, the root class name and that class's top-level bake ordinal in the process. The count is per root class name across all top-level bakes, named factories included (`bake(:admin)` with `klass: User` counts as a `User` bake). Replay the root class and ordinal printed in the explanation: a nested child reports its owner's ordinal. So a replay runs the earlier N-1 bakes of that class, then the same bake again, with the last call identical — same factory name, traits, overrides. The error text names the bake (`top-level bake #3 of User in this process`).

1. Start from the original suite command and its test-order seed. A narrower run changes which bakes ran before, and with them the ordinal.
2. Once the failure reproduces, narrow it. Check that the error still says the same `bake #N of Model`.
3. To replay bake #3 of `User` outside the suite, run the two bakes before it, then explain the third. Run it in a transaction that rolls back — the failing model's own pool: `User.transaction(requires_new: true) { ...; raise ActiveRecord::Rollback }` — plus the same wrapper around every other pool or Sequel database the graph writes to (`model.db.transaction(rollback: :always)` for Sequel), because `bake!` commits, plain `bake` can still insert raw-FK parents, and a wrapper covers exactly one connection pool; omit a wrapper only when the whole call (declarations and callbacks included) performs no database writes:

```sh
bundle exec rspec --seed 12345                                 # the original command. Minitest: bin/rails test --seed 12345
FACTORY_BAKERY_SEED=12345 RAILS_ENV=test bin/rails runner 'User.transaction(requires_new: true) { 2.times { FactoryBakery.bake(User) }; puts FactoryBakery.explain(FactoryBakery.bake(User)); raise ActiveRecord::Rollback }'
```

For a `bake!` failure, replace the last `bake` with `bake!`, and use the same verb for the warm-up bakes when earlier rows persisted (uniqueness-validated columns see them). Read the exception whenever the original verb raises (a cyclic attribute declaration raises before returning from either verb); when a record returns invalid, call `FactoryBakery.explain(record)` and read `.errors.full_messages`. Database state (rows left by earlier examples) can still differ from the suite, so a clean replay is evidence, not proof. If the runner is valid but the suite fails, replay the suite.

`FactoryBakery.explain(record)` runs `valid?` and returns the invalid attributes, the values FactoryBakery drew (`Chosen at random: ...`), the seed and a definition snippet. The snippet's `pin it in <path>` is derived from the first entry of `FactoryBakery.definition_paths` and the record's class; it does not find the real file. Locate the definition the failing target uses and edit it in place; treat the printed path as a suggestion for a new class definition. The snippet is conditional: with only an explicitly set invalid value, the explanation prints the seed and `No invalid attribute was generated at random` with no snippet. For a valid record it returns `<Class> is valid; nothing to explain.` `Chosen at random:` is provenance: it lists a filled attribute the errors name, so it shows where a value came from. It does not prove that value is the cause.

**Doctor** (Rails): `RAILS_ENV=test bin/rails 'factory_bakery:doctor[Model]'` (add `NO_FAIL=1` for exit status `0`). It runs `bake` plus `valid?`, then `bake!`, and rolls back every Active Record pool registered for the current role; effects outside those pools are not rolled back: jobs, HTTP calls and file writes that model callbacks make still happen, and Sequel databases are not covered. It prints per failing model the first error line, a hint and a link, then the rest of the error indented (the explanation). It files each failure under one of six anchors, first match wins:

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
| A WARN `left X#y_remote_url blank on purpose` | Not an error: the WARN records a skipped inferred assignment. Check the returned record or the exception for the result — a presence validation on the omitted attribute still fails `bake!`. [remote-url-left-blank](references/diagnostics.md#remote-url-left-blank) |
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
2. **A definition line** when the model needs app knowledge. Name the validator or rule that needs it. Put it in the definition the failing target actually uses, and edit that file in place. The explanation's `pin it in <file>` is derived from the first `definition_paths` entry and the class name (`<underscored class name>.rb`), so treat it as a suggestion for a new class definition, not a found file.
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

**`*_remote_url` writers.** The attribute matches the guarded-writer pattern: `remote_url`, `*_remote_url` and `remote_*url` (`ConstraintReader::REMOTE_URL_WRITER_PATTERN`). Assigning one downloads the URL: left alone, the Active Record/Active Model mapper never hands these writers a generated value; on a NOT NULL column without a default it writes `''` through the writer. Undeclared guarded writers warn once per model and attribute when the result is blank; a nonblank default survives without a warning. The WARN records a skipped inferred assignment, so keep checking the bake result: a validator may still need that attribute. When blank is not acceptable, supply a value through a definition or an override (and stub the HTTP call). `skip` drops the empty-string assignment and suppresses the warning; on a NOT NULL column without a default a skipped writer ends in `NotNullViolation` unless a presence validation raises `RecordInvalid` first. A definition or override also silences the warning. `skip` does not make an invalid record valid.

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

- `FactoryBakery.bake(Model).valid?` is `true`, and `FactoryBakery.bake!(Model)` succeeds twice in a row (catches uniqueness collisions). Bake the failing target — the class, or the named target with its traits and overrides — and put all three calls in the **same** `Model.transaction(requires_new: true) { ...; raise ActiveRecord::Rollback }` (the failing model's pool, plus the same wrapper around every other pool or Sequel database the graph writes to; for a Sequel model, `model.db.transaction(rollback: :always)`; omit a wrapper only when the whole call (declarations and callbacks included) performs no database writes) in the test environment: doctor rolls each probe back separately, so it cannot catch a collision between two consecutive `bake!` calls.
- Replay with the original seed **and** with two other seeds (`FACTORY_BAKERY_SEED=1`, `=2`). A fix that holds for one seed only is a coincidence.
- With the associations plugin, if the project uses `:all`: `FactoryBakery::Associations.with(mode: :all) { FactoryBakery.bake(Model) }`, inside the transaction wrapper, `RAILS_ENV=test`.
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
| `skip` an attribute to silence an informational WARN | Leave the WARN and check the returned record: it only records a skipped assignment, and a presence validation still fails `bake!` |
| Diagnose with `Faker::`, `rand` or `SecureRandom` left in the project's blocks | Pin them to literals first. The seed does not cover them |
| A subclass definition that copies the parent's, or forgetting it inherits | Rely on inheritance. Write one only when it must differ, with every line it needs |
| Copy the value `Chosen at random:` printed, or the snippet's `{ nil }` | A value the validator accepts |

## References

| File | Use |
| --- | --- |
| [`references/diagnostics.md`](references/diagnostics.md) | Every error: message, cause, where to look, fix, example |
| [`references/bad-patterns.md`](references/bad-patterns.md) | Diagnosis mistakes with reasons and fixes |

User guide: [`docs/guide/`](../../docs/guide/index.md). First install: [`factory-bakery-setup`](../factory-bakery-setup/SKILL.md). Migration: [`factory-bakery-migrate`](../factory-bakery-migrate/SKILL.md).
