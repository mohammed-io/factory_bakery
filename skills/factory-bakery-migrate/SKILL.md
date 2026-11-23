---
name: factory-bakery-migrate
description: Migrates a Ruby/Rails test suite from factory_bot (also fabrication, machinist, Rails fixtures and hand-rolled `create!` helpers) to FactoryBakery without changing what the tests check. Use when the user asks to migrate, convert, port or replace factory_bot / FactoryBot factories, `create(:x)` / `build(:x)` / `create_list` / `attributes_for` call sites, or to shrink factory boilerplate with FactoryBakery inference. Works in a separate git worktree, keeps the suite passing exactly as before, changes test files only by renaming factory calls, classifies each step as a one-way or two-way door, asks before simplifying definitions, and never deletes the old factories without an explicit "delete". Not for installing FactoryBakery in a project that has no migration to do (use factory-bakery-setup) and not for a bake that fails or returns an invalid record (use factory-bakery-diagnostics).
---

# Migrate to FactoryBakery

Move a codebase from another factory tool to FactoryBakery **without changing what the tests check**. FactoryBakery infers most attribute values from validators and columns, so the result is usually far fewer lines. Human version of this page: [`docs/guide/migrating-from-factory-bot.md`](../../docs/guide/migrating-from-factory-bot.md).

## The five rules

They override convenience.

1. **Isolate.** Work in a separate git worktree on a separate branch. Never touch the user's main checkout or uncommitted changes. Skip the worktree only if the user explicitly asks.
2. **The suite must pass exactly as before.** Same example count, same failures (none, if green before), **no new pending or skipped**.
3. **Test files change only by renaming factory calls.** `create(:post)` becomes `FactoryBakery.bake!(Post)`. No change to assertions, setup, expectations or structure. Anything that needs more than a rename is solved in definitions or helpers, or reported as a **blocker**.
4. **Translate 1:1 and verify green first. Simplify second, and ask.** Only after the 1:1 migration passes, propose dropping every definition line that inference already produces. The user chooses. Without an answer, keep the 1:1 translation.
5. **Doors.** Two-way doors proceed. One-way doors need explicit confirmation and happen last. **Never delete the old factories, fixtures or the gem automatically.** See [`references/doors.md`](references/doors.md).

Also: never change a model, its validations or the schema to make baking easier (a one-way door), never use `git reset --hard`, `git clean`, a force push or any history rewrite, and use the project's code-search tool (`tgrep` when an index exists).

Before the final report, check the change against [`references/bad-patterns.md`](references/bad-patterns.md).

## References

| File | Use |
| --- | --- |
| [`references/doors.md`](references/doors.md) | One-way / two-way door table, the final keep-or-delete rules |
| [`references/capability-matrix.md`](references/capability-matrix.md) | Automatic / needs a definition / not supported, with the reason per row |
| [`references/translation-rules.md`](references/translation-rules.md) | Per-construct before/after and call-site rewrites |
| [`references/caveats.md`](references/caveats.md) | Edge cases that bit real migrations |
| [`references/verification.md`](references/verification.md) | Baseline, comparison, the rename check, rollback |
| [`references/check_renames.rb`](references/check_renames.rb) | Read-only script that judges the test diff |
| [`references/other-tools.md`](references/other-tools.md) | Fabrication, machinist, fixtures, `create!` helpers |
| [`references/bad-patterns.md`](references/bad-patterns.md) | Migration mistakes with reasons and fixes |

Installing the gem is [`factory-bakery-setup`](../factory-bakery-setup/SKILL.md). A bake that fails is [`factory-bakery-diagnostics`](../factory-bakery-diagnostics/SKILL.md): tell it the call comes from this migration, so it starts at a definition line and never edits a test.

## Procedure

Run the phases in order. Each carries its door type.

### Phase 0. Isolate and baseline (two-way)

```sh
git status --short                        # note anything uncommitted. Do not touch it
git worktree add ../<repo>-bakery-migration -b factory-bakery-migration
cd ../<repo>-bakery-migration
git rev-parse HEAD                        # the starting SHA. Write it down: the final rename check needs it
```

Replace `<repo>` with the repository directory name. All work happens in that worktree.

Capture the **baseline**: the full suite's example count, failures, pending/skipped and seed ([`verification.md`](references/verification.md#1-baseline-before-any-change)). If it is not green, tell the user, and aim for "the same".

### Phase 1. Inventory (two-way, read-only)

Search the repository and write down:

- Factory files and factory count (`FactoryBot.define`, `factory :`), fabricators, machinist blueprints, fixture directories, hand-rolled `create!` helpers.
- Call-site forms: `create(`, `build(`, `build_stubbed(`, `create_list(`, `build_list(`, `create_pair(`, `attributes_for(`, and block forms `create(:x) { |x| ... }`.
- Constructs that need care or have no equivalent: `sequence`, `transient`, `after(`, `before(`, `callback(`, `initialize_with { }`, nested `factory` / `parent:`, `aliases:`, `traits_for_enum`, `skip_create`, `to_create`.
- Config: `FactoryBot.use_parent_strategy`, `FactoryBot.lint`, `definition_file_paths`.

Classify each finding with the [capability matrix](references/capability-matrix.md). Anything **not supported** that a test uses is a **blocker**. Write the blocker list now (file, line, reason) and show it to the user before spending effort on the rest.

### Phase 2. Side-by-side setup (two-way)

1. Add the gem to the test groups, then check the install **before configuring anything**. Use `gem 'factory_bakery', path: '/absolute/path/to/factory_bakery'` for a local checkout (or a git ref known to contain the features: the git remote's default branch is an older 0.0.1.0 without the generators and doctor). Then:
   ```sh
   bundle install
   bundle exec ruby -e 'require "factory_bakery"; puts FactoryBakery::VERSION'   # must be >= 0.0.2.0
   bin/rails -T factory_bakery                                                    # must list factory_bakery:doctor
   ```
2. Give FactoryBakery its **own** definitions directory, `spec/bakery` or `test/bakery`, and state it. Do not rely on factory_bot detection. `bin/rails g factory_bakery:install` creates the directory and an initializer (with `definition_paths` active when it detects factory_bot). The gem is only in the test groups, so keep production booting:
   - Wrap the whole generated `config/initializers/factory_bakery.rb` in `if defined?(FactoryBakery::Railtie) ... end`. Its template has no guard, and its `require` and `config.factory_bakery` lines fail where the gem is not loaded.
   - Put config in `config/environments/test.rb`, or guard it with `if config.respond_to?(:factory_bakery)`. In `config/application.rb` it raises `NoMethodError` at production boot.
   ```ruby
   # config/environments/test.rb
   config.factory_bakery.definition_paths = [Rails.root.join('spec/bakery').to_s]
   config.factory_bakery.associations     = { mode: :required_only }
   ```
   The initializer keeps `associations` commented, so turn it on. Do not set `config.factory_bakery.generators = true` without asking: it replaces factory_bot's generator hook. Details: [`factory-bakery-setup`](../factory-bakery-setup/SKILL.md).
3. If `FactoryBot.use_parent_strategy = false` is set, note it: edges the tests expect saved need `persist: true`.
4. Run the full suite. It must equal the baseline (nothing uses FactoryBakery yet). Commit on the migration branch.

### Phase 3. Translate definitions 1:1 (two-way)

For each factory, write the translation in the **new** directory, following [`translation-rules.md`](references/translation-rules.md). Never edit or delete the old file. Keep every attribute at first.

| factory_bot | Translation |
| --- | --- |
| `name 'x'` (static) | `name { 'x' }`. The static form raises |
| `email { "#{name}@x.com" }` | Same block. A block may read siblings |
| `sequence(:email) { \|n\| ... }` | A counter local at the top of the file |
| `association :x, name: 'a'` | `association :x, with: { name: 'a' }` |
| `association :x, :admin` | `association :x, :admin`. `:admin` is a trait on the **target's** definition, so declare it there |
| `strategy: :create` | `persist: true` |
| `author { create(:user) }` | `association :author, User, persist: true`. Keep it saved: the old factory saved the parent. If a sibling block reads `author`, keep `author { FactoryBakery.bake!(User) }`: explicit `association` runs after the attribute blocks, so a sibling cannot read it |
| `parent:` / nested factory, same class | `define(:admin, klass: User)` repeating the parent's lines, so the call stays a pure rename: `bake!(:admin)`. Not a trait, not a call-site argument |
| `class: 'Admin'` where `Admin < User` | Nothing, `Admin` inherits `User`'s definition. A subclass with its own definition replaces it, so repeat the lines it still needs |
| `skip_create`, `to_create` | **Blocker.** `bake!` always calls `save!` |
| a construct in the "not supported" class | Do not guess. Note it in the blocker list |

Run the suite after the batch. Commit.

### Phase 4. Doctor on the 1:1 translation (two-way)

Run doctor in the test environment, naming the translated models. It runs `bake` plus `valid?`, then `bake!`, rolls back the database rows, and exits `1` if any model fails (`NO_FAIL=1` to report only). Callbacks still run, so a job, an HTTP call or a file write they make is not rolled back. With no names it checks every model, including ones the tests never bake.

```sh
RAILS_ENV=test bin/rails 'factory_bakery:doctor[Post,Comment]'
```

If the task is missing (older gem), run `FactoryBakery.bake(Model).valid?` and `bake!` per model inside `ActiveRecord::Base.transaction { ...; raise ActiveRecord::Rollback }`. Failures go to the diagnostics skill. Do not simplify anything yet.

### Phase 5. Rewrite call sites. Renames only (two-way)

Small batches, one commit per batch, using [`translation-rules.md`](references/translation-rules.md#call-sites-renames-only):

- `create(:post, ...)` to `FactoryBakery.bake!(Post, ...)`
- `build(:post, ...)` to `FactoryBakery.bake(Post, ...)`
- `create_list(:post, n, ...)` to `Array.new(n) { FactoryBakery.bake!(Post, ...) }`
- `attributes_for(:post)` to `bakery_attributes_for(Post)` through a thin helper in a new `spec/support` file. If it cannot match factory_bot's output exactly (symbol keys, explicit `nil`), it is a **blocker**
- `build_stubbed` and call-site transients are **blockers**. A `create(:x) { |x| ... }` block stays on `bake!`, and a `build(:x) { |x| ... }` block stays on `bake`.

While rewriting: edit **only** the factory call, and let arguments after the name carry over unchanged. Do not touch an assertion, a `let`, a `before`, a description or a literal. If a thin helper keeps the call a rename, add it. Otherwise report the blocker.

After each batch run the suite, compare with the baseline, then the rename check ([`verification.md`](references/verification.md#3-the-rename-check)). `<skill-dir>` is the absolute path of this skill's directory. Run it on the **uncommitted** work before each commit, and against the starting SHA at the end:

```sh
git diff -U0 --no-color HEAD -- spec test | ruby <skill-dir>/references/check_renames.rb              # before each commit
git diff -U0 --no-color <start-sha> HEAD -- spec test | ruby <skill-dir>/references/check_renames.rb   # at the end
```

Any `FAIL` means stop and revert that change. Read every `REVIEW`.

### Phase 6. Verify the 1:1 migration (two-way)

| Check | Required |
| --- | --- |
| Full suite vs baseline | Same example count, same failures, same pending/skipped |
| Test diff | Renames only (rename check clean or fully reviewed) |
| `RAILS_ENV=test bin/rails 'factory_bakery:doctor[Post,Comment]'` for every baked model | Passes |
| Suite run with two different seeds (`rspec --seed A`, then `--seed B`, or `FACTORY_BAKERY_SEED`) | Same result |
| No leftover use of the old library in tests | Search `create(`, `build(`, `FactoryBot`, `Fabricate`, `.make` |

If something fails, use [`factory-bakery-diagnostics`](../factory-bakery-diagnostics/SKILL.md): reproduce with the printed seed, then fix it in a definition or helper. Never fix it by changing the test.

### Phase 7. Simplify: ask, then reduce (two-way, with a question)

Start only when Phase 6 is green and committed.

1. For each factory, compare its lines with what inference produces ([what inference covers](../../docs/guide/migrating-from-factory-bot.md#what-inference-covers)). Prepare the list of lines to drop.
2. **Ask the user** (use the agent's question tool when available) with exactly these two options, and show the drop list (model, lines, why each is covered):

   | Option | Meaning |
   | --- | --- |
   | **Reduce definitions and rely on automatic inference (recommended)** | Drop every line inference already produces. Keep a line only if a test depends on that exact value, or the model cannot bake without it |
   | **Keep a 1:1 translation of every factory** | Nothing is dropped. Safe, verbose |

3. Reduce **only if the user agrees**. If no answer is possible, keep the 1:1 translation.
4. Remove lines **one model at a time**. After each drop, re-run the tests that bake that model, and run doctor for it under three seeds:
   ```sh
   for s in 1 2 3; do FACTORY_BAKERY_SEED=$s RAILS_ENV=test bin/rails 'factory_bakery:doctor[Post]'; done
   ```
   One green run proves little: a value that fails on some seeds passes on others. If a test or a seed fails, restore the line and record why.
5. Keep a line only for one of these reasons, and say which:
   - **A test depends on that exact value** (asserts on it, or looks the record up by it).
   - **The model cannot bake without it** (custom validator, registry, format, side-effecting setter, cross-record rule, cycle, read-only view, `persist:` need). The gem does not search for an enum, boolean or STI value that passes a custom validator ([ADR-0008](../../docs/adr/0008-user-chooses-domain-values.md)), so that line stays.
6. Keep every **named** definition (`define(:admin, klass: User)`), even when every line was dropped: without it `bake!(:admin)` raises `No factory is registered for :admin`.
7. Re-run the Phase 6 checks. Commit.

### Phase 8. Report blockers and results (two-way)

Give the user the baseline and final numbers, what changed (definition files, lines kept and dropped with the reason for each kept line, helper files, call sites renamed), the **blocker list** (file, line, what would be needed), and anything not converted (fixtures, seeds, rake tasks).

### Phase 9. Ask about the old factories. The last one-way door

Only after the migration is done and the **full suite is green**. Ask the user (use the agent's question tool when available): **Keep** the old factories, or **Delete** them. Rules, in full in [`doors.md`](references/doors.md#the-last-door-old-factories):

- Delete **only** on an explicit "delete". Silence or "continue" means keep. If no answer is possible, keep, and say so.
- Search for remaining uses first (`FactoryBot`, `factory_bot`, `Fabricate`, `Fabricator`, `.blueprint`, `.make`), including seeds, rake tasks, runners and docs. Report hits and do not delete until the user decides.
- Delete in **one separate commit** (old factory files, gem entry, lockfile, nothing else), then rerun the suite. It must equal the baseline, else `git revert` the commit and report.
- Never merge or push unless the user asks. Leave the branch in the worktree.

## Bad patterns (top ones)

Full list with before/after code: [`references/bad-patterns.md`](references/bad-patterns.md).

| Do not | Do instead |
| --- | --- |
| Edit an assertion, `let` or literal to make a call fit | Rename only. Otherwise a helper, a definition, or a reported blocker |
| Skip the Phase 7 simplification decision, or simplify before the 1:1 migration is green | 1:1 first, verify, then ask. Keeping the 1:1 translation is allowed |
| Drop a line on one green doctor run | Re-run that model's tests, and doctor under `FACTORY_BAKERY_SEED=1,2,3` |
| Keep `name 'x'` | `name { 'x' }` |
| `FactoryBakery.bake!(X)` in an attribute block when `association` fits | `association :x, X, persist: true` (or `association :x, X`). Keep the block only when a sibling block reads that attribute |
| `persist: true` on every association | Only where a validator reads the parent's id, or the old factory saved the parent |
| `strategy: :fresh` on every edge | It is the default. Only where a global `:reuse_non_unique` is on |
| Cache a record in a file-level local and reuse it across bakes | One record per bake, from inside the block |
| Rely on `:reuse_non_unique` for test isolation | It reads existing rows. Use `:fresh` |
| Convert `build` to `bake!` | `build` to `bake` |
| Delete the old factories on your own | Ask, last, separate commit |
| Rewrite everything in one go | Small batches, suite after each |
| Expect the gem to pick an enum, boolean or STI value a custom validator accepts | Declare it in the definition |

## Quick decision table

| You are about to | Door | Do |
| --- | --- | --- |
| Add the gem, config, definitions, a helper | Two-way | Proceed |
| Drop a definition line | Two-way, user decision | Ask once (Phase 7), after the 1:1 migration is green |
| Rename a call site | Two-way | Proceed, one commit per batch |
| Touch an assertion, a `let`, a literal | Not allowed | Report a blocker |
| Delete factories, fabricators, blueprints, fixtures or the gem | **One-way** | Ask, last, separate commit, only on "delete" |
| Change a validation, a constraint, the schema | **One-way** | Do not. Ask and explain |
| Rewrite history, force push | **One-way** | Do not |

Rollback: [`verification.md`](references/verification.md#6-rollback).
