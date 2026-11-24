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

3. Run the rename check (below) on the uncommitted batch.
4. Commit the batch on the migration branch, one commit per batch. If the user's instructions forbid commits, leave the changes in the worktree and report.

## 3. The rename check

Every changed test line must be a factory-call rename. The helper [`check_renames.rb`](check_renames.rb) reads a unified diff and judges it. It is read-only.

```sh
git diff -U0 --no-color --no-ext-diff --no-textconv --src-prefix=a/ --dst-prefix=b/ HEAD -- spec test features engines/*/spec components/*/spec factories factories.rb | ruby <skill-dir>/references/check_renames.rb              # uncommitted work, before each commit
git diff -U0 --no-color --no-ext-diff --no-textconv --src-prefix=a/ --dst-prefix=b/ <start-sha> HEAD -- spec test features engines/*/spec components/*/spec factories factories.rb | ruby <skill-dir>/references/check_renames.rb   # the whole migration, at the end
```

Run it from the worktree. `<skill-dir>` is the absolute path of the `factory-bakery-migrate` skill directory (the script is not in the project). `<start-sha>` is the commit the worktree started from (Phase 0: `git rev-parse HEAD`). The first form checks each batch before it is committed. Only staged or tracked changes appear in a diff, so `git add` a new file first. The second form catches anything an earlier check missed. The pathspec lists every test directory Phase 1 recorded — `spec`, `test`, `features`, `engines/*/spec`, `components/*/spec` — not only `spec` and `test`. `--no-textconv` keeps external diff drivers from rewriting the stream the script parses.

| Output | Meaning | Action |
| --- | --- | --- |
| nothing for a line | A clean rename: the whitelist accepted it (one factory call per line, the verb mapped, the target kept or camelized, the text before and after the call unchanged with leading/trailing whitespace ignored, and the call's parentheses balanced on both changed lines) | Fine |
| `LIST` | `create_list`/`build_list`/`create_pair`/`build_pair` became `Array.new(n) { ... }` with the count, verb, target and arguments unchanged (a pair means 2) | Glance at it |
| `REVIEW` | Anything the whitelist does not accept, and a human reads each: every call split over lines, a changed target or namespace, a changed verb or count, a changed literal or argument, two calls on one line, a scalar call that becomes `Array.new(n)`, a whitespace-only change, a paren-less call (`create :post`, `build :user, name: 'x'`, `create_list :post, 3`, `attributes_for :post` — the valid paren-less renames such as `create :post` -> `bake! Post` are REVIEW, never FAIL), a Machinist, Fabrication or hand-rolled form (`User.make`, `User.make!`, `User.plan`, `Post.create!(attrs)`, `Post.new(attrs)`, `Fabricate(...)`), a call that keeps a receiver (only a bare `bake!(X)` via `FactoryBakery::Methods`, or `FactoryBakery.bake!(X)`, is accepted; `Helper::create(...)` and a dot with whitespace before the call are receivers too), a call sitting inside a string literal, a heredoc body or a comment (`it "uses create(:post)"`, `# create(:post)`), a target that is not a complete literal (`:post.to_s.to_sym`), a positional non-keyword argument (`create(:post, attrs)`, a bare hash, a splat), a `fill_optional:` keyword among the overrides (Bakery consumes it as an option), a binary file (`REVIEW <path>: binary file changed`), a file mode change (`REVIEW <path>: file mode changed`) | A changed verb or count is never fine: restore the mapped verb (create -> bake!, build -> bake) and the count. A changed target is fine only when it is the class the old factory built (namespaced class, quoted symbol's class, acronym class); otherwise restore it. For a split call or anything else: if only the call's spelling changed, fine; otherwise revert that line |
| `FAIL` | A non-factory edit, a `build_stubbed` / `build_stubbed_list` / `build_stubbed_pair` call, paren-less or not (a documented blocker), a hunk whose removed and added line counts differ, an edited or moved tracked factory definition file (`factories.rb` at any level, or a file under any `factories/` directory — `spec/factories/`, `test/factories/`, `factories/`, `spec/support/factories/`, ...; a mode change on a factory file does not suppress the FAIL), or input the script could not parse | **Stop.** Revert the change. Report a blocker. A wrapped `create_list` that gains a `}` line still FAILs on the line count; report it as a blocker |
| `SUPPORT FILE` | A **new** file under `spec`/`test` `bakery`/`support` (never judged — expected), and any change to `spec/rails_helper.rb`, `spec/spec_helper.rb`, `test/test_helper.rb` | Listed, never judged. Review by hand |
| `NEW FILE` | A new file under `spec` or `test` outside the bakery and support directories, typically a new spec; a copy prints `NEW FILE <to> (copy of <from>)` (a copy's added lines are not rename pairs: listed, not judged) | Not expected: a rename adds no test file. Review by hand |
| `DELETED FILE` | A file was deleted | Expected **only** in the final deletion commit (the last door) |
| `RENAMED FILE` | A file under `spec` or `test` was renamed; its edited lines are **judged**, not only listed — a rename is not a place to hide a non-factory edit | Not expected: a rename moves no test file. Review by hand |

Exit status is `1` when any `FAIL` appears. Read every `REVIEW`. The accept-set is the allowlist shape itself; a project-local helper coincidentally named create or build is silent. Read `git diff --stat` and `--summary` for binary and mode changes.

Manual cross-checks:

```sh
git diff --stat <start-sha> HEAD -- spec test       # which test files changed
git diff --numstat <start-sha> HEAD -- spec test    # added and removed lines per file
```

Expected: for each existing test file, added and removed line counts are equal (a rename is one line out, one line in). A file where they differ is suspect. New files (helpers) show only additions.

### What counts as a rename

Allowed:

- `create(:x, ...)` to `FactoryBakery.bake!(X, ...)`
- `build(:x, ...)` to `FactoryBakery.bake(X, ...)`
- `create_list` / `build_list` / `create_pair` / `build_pair` to `Array.new(n) { ... }`
- `attributes_for(:x)` to `bakery_attributes_for(X)` through the `BakeryHelpers` helper, compared against factory_bot's output per used target and trait, else a blocker
- `create(:admin)` to `bake!(:admin)` (a symbol target, for a same-class `parent:` factory registered with `define(:admin, klass: User)`)
- A new helper file, and the `RSpec.configure { |config| config.include FactoryBakery::Methods }` line inside it

Not allowed (blockers):

- Any edit to an `expect`, `assert`, `it`/`test` description, `describe`, `let`/`before` logic, or a literal outside the call
- Moving a block, adding a `reload`, adding a `before`
- Changing the number of examples

## 4. Simplification checks (Phase 7: only after the 1:1 migration is green, and the user agrees to reduce)

Remove lines **one factory at a time**, not in bulk.

1. Remove the lines the user approved for one model.
2. Run doctor under three seeds. Each must exit `0` and print `1 valid, 0 needs definition`; stop at the first failing seed:
   ```sh
   for s in 1 2 3; do FACTORY_BAKERY_SEED=$s RAILS_ENV=test bin/rails 'factory_bakery:doctor[Model]' || { echo "seed $s failed"; break; }; done
   ```
3. Re-run the tests that bake that model (search for the class name, or run the whole suite).
4. If a test or a seed now fails, **restore the line** and note the reason ("a test depends on this value" or "the model cannot bake without it"). One green run is not enough to drop a line.
5. Keep named definitions (`define(:admin, klass: User)`). A named definition never merges with the class-keyed one. Apply the keep rules per target and trait: repeat a class line only when the original named factory had it (inherited via `parent:`/nested) or the model cannot bake without it; never copy a regular factory's retained line in. After simplifying a named definition, exercise each used symbol + trait combination directly with the migrated verb — `bake!` plus `!record.new_record?` (`!record.new?` for Sequel) for a former `create` call — in the test environment inside `User.transaction(requires_new: true) { ...; raise ActiveRecord::Rollback }`, plus the same wrapper around every other pool or Sequel database the graph writes to (omit a wrapper only when the whole call, declarations and callbacks included, performs no database writes): doctor runs for class targets only.
6. Repeat for the next model.

Run the whole suite at the end, twice with different seeds (`bundle exec rspec --seed 1`, then `--seed 2`). If a run fails, replay it with the seed it printed (or the one in the FactoryBakery log line or error text) before changing anything, and use the [`factory-bakery-diagnostics`](../../factory-bakery-diagnostics/SKILL.md) skill.

## 5. Final checks (before asking about the old factories)

| Check | Command or look |
| --- | --- |
| Suite equals baseline | Full run, compare counts |
| Test diff is renames only | The rename check against `<start-sha>`, clean or fully reviewed |
| Changed files are only the expected ones | `git diff --name-only <start-sha> HEAD` is an allowlist: renamed call sites, definition and helper files, wiring committed on purpose. Anything else: stop and report |
| Every persistable class target passes doctor | `RAILS_ENV=test bin/rails 'factory_bakery:doctor[Post,Comment]'` naming every model the tests bake. Exit `0`, `N valid, 0 needs definition`. The unnamed form checks all concrete models, including framework and engine ones, and may fail on ones the tests never bake |
| Every used named target + trait combination exercised directly, with the migrated verb | A `build`-migrated target verifies with plain `bake` — it is not required to survive `bake!`. A fix in a named definition is verified by baking that named definition |
| No remaining uses of the old library in tests | Search `spec`/`test` for the call forms: `create(`, `build(`, `build_stubbed`, `attributes_for`, `_(list|pair)\(`, `FactoryBot`, `Fabricate`, `.make`, `.plan`, `srand` |
| Blockers are written down | A list with file, line, reason |

Only then ask the keep/delete question (see [doors.md](doors.md)).

## 6. Rollback

| Situation | Command |
| --- | --- |
| One batch broke the suite | `git revert <commit>` in the worktree, or `git restore .` for uncommitted work |
| A definition is wrong | Edit or delete the file in `spec/bakery`. The old factory still exists |
| The whole migration is wrong | `cd ../<repo> && git worktree remove ../<repo>-bakery-migration`, then — ask the user first, it discards the branch — `git branch -D factory-bakery-migration` |
| The deletion commit was a mistake | `git revert <deletion commit>` |
| The user's main checkout | Never touched. Nothing to roll back |

Never use `git reset --hard`, `git restore .`/`git checkout .` in the user's main checkout, `git clean`, or a force push. Never rewrite history.
