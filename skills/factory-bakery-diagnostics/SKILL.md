---
name: factory-bakery-diagnostics
description: Diagnose why a model does not bake with FactoryBakery. Use when `FactoryBakery.bake` or `bake!` raises (FactoryBakery::Error, IncompletePersistenceError, CyclicAssociationError, ReadOnlyTargetError, NestingTooDeepError, ArgumentError from the association DSL), when a baked record is invalid, when a value is silently nil or wrong, when `bin/rails factory_bakery:doctor` reports a failing model, or when the user pastes a FactoryBakery error message. Gives a procedure to reproduce, classify, and apply the smallest fix (call-site override, definition line, persist:, with:, skip, or a gem bug report).
---

# Diagnose a FactoryBakery bake failure

Use this when a model does not bake, or bakes into the wrong record. The catalog of every error is in [`references/diagnostics.md`](references/diagnostics.md). Anchors there are stable.

## Rules

- Make the **smallest** change that fixes the bake. Prefer an override, then one definition line, then `persist:`, `with:`, `skip`.
- Do **not** change the model, its validations or the schema to make baking easier. That is a one-way door: ask the user first.
- Do not delete or rewrite existing definitions beyond the failing line.
- Do not guess. Reproduce first, then match the message to the catalog.
- Search the code with the project's code-search tool. Use the `tgrep` index when the project has one.

## Procedure

### 1. Reproduce

Run the smallest command that fails, in the app's test environment:

```sh
bin/rails runner -e test 'm = FactoryBakery.bake(Model); p m.valid?, m.errors.full_messages'
bin/rails runner -e test 'FactoryBakery.bake!(Model)'
```

Run each model on its own, so one failure does not hide another. Wrap in a transaction you roll back if the app uses a real database.

If `bin/rails factory_bakery:doctor[Model]` exists, run it first. It prints the error, a hint and an anchor. <!-- verify against implementation -->

Record three facts: the exception class, the full message, and whether it fails under `bake`, `bake!` or both.

### 2. Read the error

| What you see | Do this |
| --- | --- |
| A `FactoryBakery::Error` (or subclass) or an `ArgumentError` naming FactoryBakery concepts | Look the message up in the catalog's [index by message](references/diagnostics.md#index-by-message) |
| `bake` returns a record that is not valid | Read `errors.full_messages`. Go to step 3 |
| `ActiveRecord::RecordInvalid` from `bake!` | Same as above |
| A database error (`NotNullViolation`, `InvalidForeignKey`, unique violation) | [db-only-constraints](references/diagnostics.md#db-only-constraints) or [has-one-created-by-callback](references/diagnostics.md#has-one-created-by-callback) |
| No error, wrong value | [silent-failures](references/diagnostics.md#silent-failures) |

### 3. Classify

Pick exactly one class.

| Class | Signs | Catalog |
| --- | --- | --- |
| **Definition or DSL mistake** | Unknown trait, unregistered symbol, `skip` misuse, option errors, plugin not loaded | `unregistered-factory`, `unknown-trait`, `association-plugin-not-loaded`, `association-option-errors` |
| **Association graph** | Cycle, nesting, polymorphic target, `must exist`, wrong parent reused | `cyclic-association`, `no-polymorphic-target-discovered`, `must-exist-error`, `reuse-picks-owners-own-parent` |
| **Persistence** | `did not persist`, read-only, a validator reading an id, callback-created rows | `incomplete-persistence`, `read-only-target`, `id-reading-custom-validator`, `has-one-created-by-callback` |
| **Value generation** | `could not generate ...` | `unique-value-collisions`, `format-exhaustion`, `numeric-constraint-exhaustion` |
| **App rule inference cannot know** | Registry, setting, time rule, structured text, side-effecting setter | `registry-and-inclusion-lists`, `time-relative-validations`, `structured-text-columns`, `side-effecting-writers` |
| **Gem defect** | A declared, discoverable constraint mishandled | See step 5 |

### 4. Fix with the smallest change

Apply the fix named in the catalog entry. Order of preference:

1. **A call-site override** in the test that needs a particular value.
2. **A definition line** when the model needs app knowledge. Say why: which validator or rule needs it. Put it in the definitions directory the project uses (`spec/bakery`, `spec/factories`, `test/factories`).
3. **`association :x, persist: true`** when a validator reads a parent's id.
4. **`with: { ... }`** for child attributes on an association.
5. **`skip :x`** for a side-effecting setter, a read-only view edge, or a cycle.
6. **`strategy: :fresh`** when a reused parent breaks a rule on that edge.

Examples, by situation:

```ruby
# a validator reads a parent's id (Discourse TopicLink)
association :topic, persist: true, with: { user: Discourse.system_user }

# two edges to one class: persist both (see nested-bake-sibling-of-same-class)
association :user, persist: true
association :invited_by, persist: true

# a registry value (Discourse AdminDashboardReport)
source { 'core_report' }

# a side-effecting setter (Mastodon Account)
skip :avatar_remote_url

# a view as a parent (Mastodon InstanceModerationNote)
skip :instance
domain { 'example.com' }

# a cycle in :all (Mastodon Account)
skip :moved_to_account
```

Never use `name 'x'` (no block) in a definition: it assigns nothing and suppresses inference. Use `name { 'x' }`.

### 5. Or report a gem bug

Report it only when **all** of these hold:

1. The failing rule is a declared validator or column constraint, not app logic.
2. A minimal model reproduces it with `FactoryBakery.bake(Model)` alone.
3. A definition line would only be a workaround.

File it in the GitHub issues of `mohammed-io/factory_bakery` (see `docs/agents/issue-tracker.md`; use the `needs-triage` label). Include `FactoryBakery::VERSION`, the model, the validator, the exact message and the repro. Meanwhile apply the definition-line workaround and leave a comment with the issue link above it.

### 6. Verify

- `FactoryBakery.bake(Model).valid?` is `true`.
- `FactoryBakery.bake!(Model)` succeeds, twice in a row (catches uniqueness collisions).
- With the associations plugin: also try `Associations.with(mode: :all) { FactoryBakery.bake(Model) }` if the project uses `:all`.
- Run the affected tests. They must pass exactly as before.
- Run `bin/rails factory_bakery:doctor[Model]` if available. <!-- verify against implementation -->

## Common first checks (fast path)

1. Is the associations plugin loaded? (`FactoryBakery::PluginRegistry.plugins.size`). A `must exist` error means no.
2. Are definitions loaded from the right directory? (`FactoryBakery.definition_paths`).
3. Is the failure only with `:all`, or only with `:reuse_non_unique`? Reproduce under `Associations.with(...)`.
4. Does a custom validator read an `_id`? Use `persist: true`.
5. Is the code path touching the network, a registry, or "now"? That is app-specific setup: a definition line.

## References

- [`references/diagnostics.md`](references/diagnostics.md): every error, with cause, where to look, fix, examples.
- User guide: [`docs/guide/`](../../docs/guide/index.md).
- If the project still uses factory_bot, see the [`factory-bakery-migrate`](../factory-bakery-migrate/SKILL.md) skill.
