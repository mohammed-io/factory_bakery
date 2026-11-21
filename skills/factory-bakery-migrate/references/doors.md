# One-way and two-way doors

Every migration step is one of two kinds.

- **Two-way door.** Cheap to undo. Do it, verify it, move on.
- **One-way door.** Hard or impossible to undo. Never do it without the user's **explicit confirmation**. Do all of them **last**, after the full suite is green.

Deleting the old factories, fabricators, blueprints, fixtures and the `factory_bot` gem is the **last** one-way door. It is never done automatically. See the final row.

## Two-way doors: proceed

| Step | Why it is cheap to undo | Undo |
| --- | --- | --- |
| Create the worktree and branch | The main checkout is untouched | `git worktree remove ../<repo>-bakery-migration` and `git branch -D factory-bakery-migration` |
| Add the `factory_bakery` gem | One Gemfile line | Remove the line, `bundle install` |
| Side-by-side config (`definition_paths`, `associations`) | Config only. The old library still works | Remove the config |
| Create `spec/bakery` (or `test/bakery`) | New directory the old library does not read | Delete the directory |
| Add FactoryBakery definitions | New files in the new directory | Delete the files |
| Simplify a **new** definition (drop a line) | The old factory is untouched | Add the line back |
| Add a thin helper in `spec/support` (for `attributes_for` and the like) | New file | Delete it |
| Rename call sites in a batch, one commit per batch | Pure text rename, in a commit | `git revert` the commit |
| Run `factory_bakery:doctor` | Rolled back. Writes nothing | Nothing to undo. (`WRITE=1` writes stubs: that is adding definitions, also two-way) |
| Run the suite, capture the baseline | Read-only | Nothing |

## One-way doors: ask first, do last

| Step | Why it is hard to undo | Rule |
| --- | --- | --- |
| **Delete the factory_bot factories** | Their content is gone from the working tree. `git revert` can restore it, but only if the deletion was an isolated commit | Only on an explicit "delete" answer. Separate commit |
| **Remove the `factory_bot` / `factory_bot_rails` gem** | The lockfile and other branches change. Other code may still use it | Same commit as the factory deletion, only on "delete" |
| **Delete fabricators, machinist blueprints** | Same as factories | Same rule |
| **Delete Rails fixtures** (`test/fixtures`, `spec/fixtures`) | Tests, seeds and other tools may load them by name. Converting them changes tests | Never automatic. Report. Ask separately |
| **Change DB constraints or app validations** to make baking easier | Changes production behavior and data rules | Never as part of a migration. Ask, and explain why |
| **Remove test data the suite relies on** | Tests can pass or fail for hidden reasons | Never without a reason the user approves |
| **Squash or rewrite history** (`rebase -i`, `reset --hard`, force push) | Loses the revert path | Never |
| **Move `spec/bakery` back to `spec/factories`** and unset `definition_paths` | Looks harmless, but a stale `spec/factories` file may be reloaded | Do after deletion, as its own commit, if the user wants it |
| **Edit assertions, setup or test structure** | Breaks the "same tests" guarantee | Not allowed. Report as a blocker |
| **Merge or push the migration branch** | Shares the change | Only if the user asks |

## The last door: old factories

After the whole migration is done and the full suite is green, **ask**. Never decide for the user. Present both options:

| Option | Meaning |
| --- | --- |
| **Keep the old factories** | Nothing is deleted. The `factory_bot` gem, its files and the side-by-side directory stay. The repository carries two factory systems until the user decides. Safe |
| **Delete the old factories** | The old factory files and the gem are removed in **one separate commit** that touches nothing else, so it can be reverted with `git revert`. The suite is run again and must still match the baseline |

Rules:

1. Delete **only** on an explicit "delete" answer. Silence, "ok", "looks good" or "continue" is not a "delete" answer.
2. If no answer can be obtained (a non-interactive run), **keep**. Report that the old files were left.
3. Before deleting, check nothing still calls the old library: search the repository for `FactoryBot`, `factory_bot`, `Fabricate`, `Fabricator`, `.blueprint`, `.make`. Seeds, rake tasks, rails runners and docs are included. Report any hit and do not delete until the user decides.
4. The deletion is **one commit**: the old factory files and the gem entry (with the lockfile). Nothing else.
5. After the commit, run the full suite. It must match the baseline. If it does not, `git revert` the commit and report.

## Using this table

Before each step, ask: *if this is wrong, can I undo it with one command and no loss?* If yes, proceed. If no, stop and ask.
