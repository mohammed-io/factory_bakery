---
name: factory-bakery-migrate
description: Migrate a Ruby/Rails codebase from factory_bot (and also fabrication, machinist, Rails fixtures, or hand-rolled `create!` helpers) to FactoryBakery. Use when the user asks to migrate, convert, port, or replace factory_bot / FactoryBot factories, `create(:x)` / `build(:x)` call sites, `create_list`, `attributes_for`, or to reduce factory boilerplate with FactoryBakery inference. Works in a separate git worktree, keeps the test suite passing exactly as before, changes test files only by renaming factory calls, classifies each step as a one-way or two-way door, asks before simplifying definitions, and never deletes the old factories without an explicit "delete" answer.
---

# Migrate to FactoryBakery

You move a codebase from another factory tool to FactoryBakery **without changing what the tests check**. FactoryBakery infers most attribute values from validators and columns, so the result is usually far fewer lines. See the human guide: [`docs/guide/migrating-from-factory-bot.md`](../../docs/guide/migrating-from-factory-bot.md).

## The five rules

Follow these exactly. They override convenience.

1. **Isolate.** Work in a separate git worktree on a separate branch. Never touch the user's main checkout or their uncommitted changes. Skip the worktree only if the user explicitly asks.
2. **The suite must pass exactly as before.** Same example count, same failures (none, if green before), **no new pending or skipped**.
3. **Test files change only by renaming factory calls.** `create(:post)` becomes `FactoryBakery.bake!(Post)`. No change to assertions, setup, expectations or structure. Anything that needs more than a rename is solved in definitions or helpers, or reported to the user as a **blocker**.
4. **Simplify by default, but ask.** Propose dropping every definition line that inference already produces. The user chooses. Without an answer, keep a 1:1 translation.
5. **Doors.** Two-way doors proceed. One-way doors need explicit confirmation and happen last. **Never delete the old factories, fixtures or the gem automatically.** The final step asks keep or delete. See [`references/doors.md`](references/doors.md).

Also: never change the model, its validations or the schema to make baking easier. That is a one-way door and is not part of this migration.

## References

| File | Use |
| --- | --- |
| [`references/doors.md`](references/doors.md) | The one-way / two-way door table and the final keep-or-delete rules |
| [`references/capability-matrix.md`](references/capability-matrix.md) | Automatic / needs a definition / not supported, with the reason for each row |
| [`references/caveats.md`](references/caveats.md) | Every edge case and caveat |
| [`references/translation-rules.md`](references/translation-rules.md) | Per-construct before/after, call-site rewrites |
| [`references/verification.md`](references/verification.md) | Baseline, comparison, the rename check, rollback |
| [`references/check_renames.rb`](references/check_renames.rb) | A read-only script that judges the test diff |
| [`references/other-tools.md`](references/other-tools.md) | Fabrication, machinist, fixtures, `create!` helpers |

Setup of the gem itself is the [`factory-bakery-setup`](../factory-bakery-setup/SKILL.md) skill. A bake that fails is the [`factory-bakery-diagnostics`](../factory-bakery-diagnostics/SKILL.md) skill.

Use the project's code-search tool for all searching (`tgrep` when an index exists).

## Procedure

Each phase is labelled with its door type. Run the phases in order.

### Phase 0. Isolate and baseline (two-way)

```sh
git status --short                        # note anything uncommitted. Do not touch it
git worktree add ../<repo>-bakery-migration -b factory-bakery-migration
cd ../<repo>-bakery-migration
```

Replace `<repo>` with the repository directory name. All work happens in that worktree. Never `cd` back to edit the main checkout.

Then capture the **baseline**: run the full suite and record the example count, failures and pending/skipped (commands in [`verification.md`](references/verification.md#1-baseline-before-any-change)). If it is not green, tell the user what the baseline is, and aim for "the same".

### Phase 1. Inventory (two-way, read-only)

Search the repository and write down:

- Factory files and the number of factories (`FactoryBot.define`, `factory :`), fabricators, machinist blueprints, fixture directories, hand-rolled `create!` helpers.
- Call-site forms: `create(`, `build(`, `build_stubbed(`, `create_list(`, `build_list(`, `create_pair(`, `attributes_for(`, with block form `create(:x) { |x| ... }`.
- Constructs with no equivalent: `sequence`, `transient`, `after(`, `before(`, `callback(`, `initialize_with { }`, nested `factory`/`parent:`, `aliases:`, `traits_for_enum`.
- Config: `FactoryBot.use_parent_strategy`, `FactoryBot.lint`, `definition_file_paths`.

Classify each finding with the [capability matrix](references/capability-matrix.md). Anything **not supported** that a test uses is a **blocker**. Write the blocker list now (file, line, reason). Show it to the user before spending effort on the rest.

### Phase 2. Side-by-side setup (two-way)

1. Add the gem to the test groups of the Gemfile. Run `bundle install`.
2. Give FactoryBakery its **own** definitions directory: `spec/bakery` (RSpec) or `test/bakery` (Minitest). **Edge case:** without factory_bot both gems would default to `spec/factories` and `test/factories` and load each other's files. FactoryBakery switches its default to `spec/bakery`/`test/bakery` when it detects factory_bot, but do not rely on that. Run `bin/rails g factory_bakery:install` (creates the directory and an initializer with `config.definition_paths = ["spec/bakery"]`), or set by hand:
   ```ruby
   config.factory_bakery.definition_paths = [Rails.root.join('spec/bakery').to_s]
   config.factory_bakery.associations     = { mode: :required_only }
   ```
   The initializer keeps `associations` commented. Turn it on there or in `config/application.rb`. The `bin/rails g model` hook only writes a FactoryBakery stub when no other `fixture_replacement` (such as `:factory_bot`) is selected. During the migration use `bin/rails g factory_bakery:definition Post` explicitly. Setting `config.factory_bakery.generators = true` would replace the factory_bot hook, so ask first.
3. If `FactoryBot.use_parent_strategy = false` is set, note it: edges the tests expect saved need `persist: true`.
4. Run the full suite. It must equal the baseline. Nothing uses FactoryBakery yet.
5. Commit on the migration branch.

### Phase 3. Translate definitions 1:1 (two-way)

For each factory, write the translation in the **new** directory, following [`translation-rules.md`](references/translation-rules.md). Do not edit or delete the old file.

- Keep every attribute at first. This phase is a faithful 1:1 translation.
- Static `name 'x'` becomes `name { 'x' }`.
- `sequence` becomes a counter local at the top of the file.
- `association :x, name: 'a'` becomes `association :x, with: { name: 'a' }`. `strategy: :create` becomes `persist: true`.
- Nested/inherited factories become traits or a second definition.
- A construct in the "not supported" class: do not guess. Leave a note in the blocker list.

Run the suite after the batch. Commit.

### Phase 4. Doctor, then ask to simplify (two-way, with a question)

1. Run `bin/rails 'factory_bakery:doctor[Post,Comment]'` with the names of the translated models. It runs `bake` plus `valid?`, then `bake!`, rolled back, and exits `1` if any model fails (`NO_FAIL=1` to report only). With no names it checks every model, including ones your tests never bake. If the task is missing (an older gem), run `FactoryBakery.bake(Model).valid?` and `bake!` per model in a rolled-back transaction.
2. For each factory, compare its lines to what inference produces (see [what inference covers](../../docs/guide/migrating-from-factory-bot.md#what-inference-covers)). Prepare the list of lines you would drop.
3. **Ask the user** (use the agent's question tool when available). Present exactly these two options:

   | Option | Meaning |
   | --- | --- |
   | **Reduce definitions and rely on automatic inference (recommended)** | Drop every line inference already produces. Keep a line only if a test depends on that exact value, or the model cannot bake without it |
   | **Keep a 1:1 translation of every factory** | Nothing is dropped. Safe, verbose |

   Show the proposed drop list (model, lines dropped, the reason each is covered) so the answer is informed.
4. Take the recommended option **only if the user agrees**. If no answer is possible, keep the 1:1 translation.
5. When reducing, remove lines **one model at a time**, running doctor and the tests for that model after each. If a test fails, restore the line and record the reason. Keep a line only for one of these reasons, and say which:
   - **A test depends on that exact value** (it asserts on it, or looks the record up by it).
   - **The model cannot bake without it** (custom validator, registry, format, side-effecting setter, cross-record rule, cycle, read-only view, `persist:` need).
6. Commit.

### Phase 5. Rewrite call sites. Renames only (two-way)

Rewrite the call sites in small batches, one commit per batch, using the table in [`translation-rules.md`](references/translation-rules.md#call-sites-renames-only):

- `create(:post, ...)` to `FactoryBakery.bake!(Post, ...)`
- `build(:post, ...)` to `FactoryBakery.bake(Post, ...)`
- `create_list(:post, n, ...)` to `Array.new(n) { FactoryBakery.bake!(Post, ...) }`
- `attributes_for(:post)` to `attributes_for(Post)` via a thin helper in `spec/support` (a new file)
- `build_stubbed` and call-site transients are **blockers**. Keep existing `create(:x) { block }` blocks on `bake!`.

Rules while rewriting:

- Edit **only** the factory call. Arguments after the name carry over unchanged.
- Do not edit an assertion, a `let`, a `before`, a description or a literal.
- If a thin helper keeps the call a rename, add it. Otherwise report the blocker.
- After each batch: run the suite, compare with the baseline, run the rename check ([`verification.md`](references/verification.md#3-the-rename-check)):
  ```sh
  git diff -U0 --no-color <base-branch>...HEAD -- spec test | ruby <path>/check_renames.rb
  ```
  Any `FAIL` means stop and revert that change. Read every `REVIEW`.

### Phase 6. Verify (two-way)

| Check | Required |
| --- | --- |
| Full suite vs baseline | Same example count, same failures, same pending/skipped |
| Test diff | Renames only (rename check clean or fully reviewed) |
| `factory_bakery:doctor` for every baked model | Passes |
| Run the suite with two different seeds | Same result |
| No leftover use of the old library in tests | Search `create(`, `build(`, `FactoryBot`, `Fabricate`, `.make` |

If something fails, use the [`factory-bakery-diagnostics`](../factory-bakery-diagnostics/SKILL.md) skill. Fix it in a definition or helper. Never fix it by changing the test.

### Phase 7. Report blockers and results (two-way)

Give the user:

- The baseline and final numbers.
- What changed: definition files, number of lines kept/dropped (and the reasons for lines kept), helper files, call sites renamed.
- The **blocker list**: each unsupported construct a test uses, with file, line and what would be needed.
- Anything you did not convert (fixtures, seeds, rake tasks).

### Phase 8. Ask about the old factories. The last one-way door

Only after the whole migration is done and the **full suite is green**. **Never delete automatically.** Ask the user (use the agent's question tool when available) with both options and what each implies:

| Option | Meaning |
| --- | --- |
| **Keep the old factories** | Old factory files and the `factory_bot` gem stay. Nothing is lost. Two factory systems remain until the user decides |
| **Delete the old factories** | The old factory files and the gem are removed in **one separate commit** that changes nothing else, so it can be reverted with `git revert`. The suite is run again and must equal the baseline |

Rules:

- Delete **only** on an explicit "delete" answer. Silence or "continue" means **keep**.
- If no answer is possible, **keep**, and say so in the report.
- First search the repository for remaining uses (`FactoryBot`, `factory_bot`, `Fabricate`, `Fabricator`, `.blueprint`, `.make`), including seeds, rake tasks, runners and docs. If there are hits, report them and do not delete until the user decides.
- The deletion commit contains the old factory/fabricator/blueprint files and the gem entry plus the lockfile. Nothing else. Fixtures are never included without their own explicit question.
- After the commit, run the full suite. It must equal the baseline. If it does not, `git revert` the commit and report.

Leave the branch in the worktree. Do **not** merge or push unless the user asks.

## Rollback

| Situation | Action |
| --- | --- |
| A batch broke the suite | `git revert` that commit in the worktree |
| The migration is wrong | `git worktree remove ../<repo>-bakery-migration` then `git branch -D factory-bakery-migration`. The main checkout was never touched |
| The deletion commit was a mistake | `git revert <deletion commit>` |

Never use `git reset --hard`, `git clean`, a force push or any history rewrite.

## Quick decision table

| You are about to | Door | Do |
| --- | --- | --- |
| Add the gem, config, definitions, a helper | Two-way | Proceed |
| Drop a definition line | Two-way, but a user decision | Ask once (Phase 4) |
| Rename a call site | Two-way | Proceed, one commit per batch |
| Touch an assertion, a `let`, a literal | Not allowed | Report a blocker |
| Delete factories, fabricators, blueprints, fixtures, or the gem | **One-way** | Ask, last, separate commit, only on "delete" |
| Change a validation, a constraint, the schema | **One-way** | Do not. Ask the user and explain |
| Rewrite history, force push | **One-way** | Do not |
