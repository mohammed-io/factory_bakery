# Verification, baseline, and rollback

The migration is correct only when the suite passes **exactly as before** and the test diff holds nothing but factory-call renames.

## 1. Baseline (before any change)

In the worktree, before the first edit, run the full suite and record the numbers.

```sh
bundle exec rspec 2>&1 | tail -5       # RSpec: "N examples, F failures, P pending"
bin/rails test 2>&1 | tail -5          # Minitest: "N runs, A assertions, F failures, E errors, S skips"
```

Write the line into the migration notes. Also record, per run:

| Item | RSpec | Minitest |
| --- | --- | --- |
| Example/test count | `examples` | `runs` |
| Failures | `failures` | `failures`, `errors` |
| Pending/skipped | `pending` | `skips` |
| Seed | `Randomized with seed N` | `Run options: --seed N` |

If the baseline has failures, **stop and tell the user**. The target is "the same as before". A failing baseline means "the same failures".

Run once more with the same seed to confirm the baseline is stable (flaky tests are listed and excluded from judgment, not fixed).

After the migration, the same `--seed N` also fixes FactoryBakery's generated values for the same bakes in the same order, provided `factory_bakery/rspec` (or `/minitest`) is required. Without it, each process draws a random seed and logs it at WARN. `FACTORY_BAKERY_SEED=N` pins it either way and outranks the framework seed.

## 2. After each batch

1. Run the affected files, then the full suite.
2. Compare with the baseline:

   | Check | Required |
   | --- | --- |
   | Example/test count | Identical |
   | Failures | Identical to baseline (zero if the baseline was green) |
   | Pending/skipped | Identical. **No new pending or skipped** |
   | Warnings about deprecations | No new ones from the migration |

3. Run the rename check (below).
4. Commit the batch on the migration branch, one commit per batch. If the user's instructions forbid commits, leave the changes in the worktree and report.

## 3. The rename check

Every changed test line must be a factory-call rename. The helper [`check_renames.rb`](check_renames.rb) reads a unified diff and judges it. It is read-only.

```sh
git diff -U0 --no-color <base-branch>...HEAD -- spec test | ruby <skill-dir>/references/check_renames.rb
```

Run it from the worktree. `<skill-dir>` is the absolute path of the `factory-bakery-migrate` skill directory (the script is not in the project). Replace `<base-branch>` with the branch the worktree started from (often `main`).

| Output | Meaning | Action |
| --- | --- | --- |
| nothing for a line | A clean rename | Fine |
| `LIST` | `create_list`/`build_list`/`*_pair` became `Array.new(n) { ... }` | Glance at it |
| `REVIEW` | The pair differs by more than the call (an argument, a literal, a trait) | Open it. If it is only the call, fine. If anything else changed, **revert that line** |
| `FAIL` | A changed line is not a factory call, or line counts differ | **Stop.** Revert the change. Report a blocker |
| `NEW FILE` | A new helper or definition file | Review by hand. New files under `spec/support` and `spec/bakery` are expected |
| `DELETED FILE` | A file was deleted | Expected **only** in the final deletion commit (the last door) |

Exit status is `1` when any `FAIL` appears. The script judges lines. It does not understand Ruby, so it can miss a rename that also alters a nearby token on the same line. Read every `REVIEW` and skim the whole `git diff --stat` too.

Manual cross-checks:

```sh
git diff --stat <base>...HEAD -- spec test       # which test files changed
git diff --numstat <base>...HEAD -- spec test    # added and removed lines per file
```

Expected: for each existing test file, added and removed line counts are equal (a rename is one line out, one line in). A file where they differ is suspect. New files (helpers) show only additions.

### What counts as a rename

Allowed:

- `create(:x, ...)` to `FactoryBakery.bake!(X, ...)`
- `build(:x, ...)` to `FactoryBakery.bake(X, ...)`
- `create_list` / `build_list` / `create_pair` to `Array.new(n) { ... }`
- `attributes_for(:x)` to `attributes_for(X)` (through a helper)
- A new helper file, and an `RSpec.configure` include inside it

Not allowed (blockers):

- Any edit to an `expect`, `assert`, `it`/`test` description, `describe`, `let`/`before` logic, or a literal outside the call
- Moving a block, adding a `reload`, adding a `before`
- Changing the number of examples

## 4. Simplification checks (after the user agrees to reduce)

Remove lines **one factory at a time**, not in bulk.

1. Remove the lines the user approved for one model.
2. Run `bin/rails 'factory_bakery:doctor[Model]'`. It must exit `0` and print `1 valid, 0 needs definition`.
3. Run the tests that bake that model (search for the class name, or run the whole suite).
4. If a test now fails, **restore the line** and note the reason ("a test depends on this value" or "the model cannot bake without it").
5. Repeat for the next model.

Run the whole suite at the end, twice with different seeds (`bundle exec rspec --seed 1`, then `--seed 2`). If a run fails, replay it with the seed it printed (or the one in the FactoryBakery log line or error text) before changing anything, and use the [`factory-bakery-diagnostics`](../../factory-bakery-diagnostics/SKILL.md) skill.

## 5. Final checks (before asking about the old factories)

| Check | Command or look |
| --- | --- |
| Suite equals baseline | Full run, compare counts |
| Test diff is renames only | The rename check, clean or fully reviewed |
| Every baked model passes doctor | `bin/rails 'factory_bakery:doctor[Post,Comment]'` naming every model the tests bake. Exit `0`, `N valid, 0 needs definition`. The unnamed form checks all models and may fail on ones the tests never bake |
| No remaining uses of the old library in tests | Search `spec`/`test` for `create(`, `build(`, `create_list`, `FactoryBot`, `Fabricate`, `.make` |
| Blockers are written down | A list with file, line, reason |

Only then ask the keep/delete question (see [doors.md](doors.md)).

## 6. Rollback

| Situation | Command |
| --- | --- |
| One batch broke the suite | `git revert <commit>` in the worktree, or `git restore .` for uncommitted work |
| A definition is wrong | Edit or delete the file in `spec/bakery`. The old factory still exists |
| The whole migration is wrong | `cd ..; git worktree remove ../<repo>-bakery-migration; git branch -D factory-bakery-migration` |
| The deletion commit was a mistake | `git revert <deletion commit>` |
| The user's main checkout | Never touched. Nothing to roll back |

Never use `git reset --hard`, `git checkout .` in the user's main checkout, `git clean`, or a force push. Never rewrite history.
