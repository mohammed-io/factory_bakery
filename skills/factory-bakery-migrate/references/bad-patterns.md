# Migration bad patterns

Each entry: the pattern, why it hurts, what to do instead. Claims are checked against `lib/` and `docs/guide/`. An entry marked *(reasoned, not run)* follows from documented behavior but was not executed.

Contents: [edit the test](#1-editing-assertions-lets-or-literals-instead-of-renaming-calls) · [skip the simplify decision](#2-skipping-the-simplification-decision) · [static attributes](#3-static-name-x) · [class vs symbol key](#4-a-symbol-definition-called-by-class) · [bake! in a block](#5-factorybakerybakex-inside-an-attribute-block) · [persist everywhere](#6-persist-true-on-every-association) · [fresh everywhere](#7-strategy-fresh-everywhere) · [memoized record](#8-memoizing-a-record-across-bakes) · [reuse for isolation](#9-relying-on-reuse_non_unique-for-isolation) · [build to bake!](#10-converting-build-to-bake) · [subclass copies](#11-copying-a-parents-lines-into-a-subclass-definition) · [auto-delete](#12-deleting-the-old-factories-automatically) · [big bang](#13-a-big-bang-rewrite) · [history rewrites](#14-git-reset---hard-or-history-rewrites) · [domain values](#15-expecting-the-gem-to-pick-a-value-a-custom-validator-accepts) · [one green run](#16-dropping-a-definition-line-on-one-green-doctor-run)

## 1. Editing assertions, lets or literals instead of renaming calls

**Why it hurts.** The migration promises the tests check the same things. An edited assertion can pass for a different reason, and the rename check (`check_renames.rb`) reports a `FAIL` or `REVIEW` for it.

```ruby
# bad: the call and the assertion both changed
-  expect { create(:post) }.to change(Post, :count).by(1)
+  expect { FactoryBakery.bake!(Post) }.to change { Post.count }.by(2)

# good: the call renamed, nothing else
+  expect { FactoryBakery.bake!(Post) }.to change(Post, :count).by(1)
```

**Instead.** If the count differs, the graph differs: fix it in a definition (an `association` line) or report a blocker. Never in the test.

## 2. Skipping the simplification decision

**Why it hurts.** A 1:1 translation keeps lines inference already produces (Faker names, sequences on uniqueness-validated columns, required `association` lines). Keeping it is allowed, but only as the user's answer. Translating everything and never asking leaves the migration buying nothing, and the lines keep hiding which ones a model really needs. The opposite mistake is simplifying before the 1:1 migration is green: a failure then has two possible causes.

**Instead.** Finish and verify the 1:1 migration (Phase 6). Then run Phase 7: the drop list, the two-option question, and, if the user agrees, remove lines one model at a time, keeping only lines a test asserts on or the model cannot bake without. If the user says keep, keep.

```ruby
# 1:1 translation
FactoryBakery.define(User) do
  name { Faker::Name.name }
  email { "user#{counter += 1}@example.com" }
  role { 'member' }
  association :account
end

# after the approved reduce step: nothing is left to say. A named definition never merges
# with the class-keyed one: apply the keep rules per target and trait, repeating a class
# line only when the original named factory had it (parent:/nested) or the model cannot
# bake without it — never a copied retained line from the regular factory (probed: it
# turns a nil name into the class-keyed definition's kept value)
```

## 3. Static `name 'x'`

**Why it hurts.** The static form raises when the definition is evaluated: `Static attributes are unsupported; use name { "x" }`.

```ruby
# bad
name 'Ada'
# good
name { 'Ada' }
```

If the line is only there to give some name, drop it instead (a NOT NULL `name` is filled).

## 4. A symbol definition called by class

**Why it hurts.** Class and symbol registrations are separate keys. `define(:post, klass: Post)` is reached only by `bake(:post)`, so `bake!(Post)` ignores it, with no error ([definitions.md](../../../docs/guide/definitions.md#named-factories)).

```ruby
# bad: the call sites say bake!(Post)
FactoryBakery.define(:post, klass: Post) { title { 'x' } }

# good: factory name equals the class
FactoryBakery.define(Post) { title { 'x' } }
```

Use a symbol with `klass:` only when tests create the same class under several names or the factory name differs from the class, and keep the symbol at the call site (`bake!(:admin)`).

## 5. `FactoryBakery.bake!(X)` inside an attribute block

**Why it hurts.** It is the literal translation of `author { create(:user) }`, but it hides the edge from the DSL. `association` checks the edge name at bake time (`Post has no association :nope`), accepts `with:`, traits and `count:`, and lets plain `bake` leave the parent unsaved. A block writes a row even under `bake`, and a mistyped attribute name in a block is skipped silently (a missing setter is not an error).

```ruby
# bad
author { FactoryBakery.bake!(User) }

# good: unsaved parent, saved with the owner by bake!
association :author, User

# good: only when a validator reads the parent's id
association :author, User, persist: true
```

A block that bakes is right for what the DSL refuses or cannot see: `has_many :through` and HABTM, registry-backed lookups, cross-record rules (Mastodon `AccountPin` bakes a `Follow`), Sequel models.

It is also right when a **sibling block reads the attribute**. With an explicit `association` ([definitions guide](../../../docs/guide/definitions.md)), a sibling block that reads it gets nil and the edge is then not built at all (the record can end up invalid), so `name { "#{author.name}'s post" }` breaks. Keep the attribute block there instead of rewriting it. And keep `persist: true` on the rewrite where the old factory saved the parent (`author { create(:user) }`, `strategy: :create`): `association :author, User` alone leaves it unsaved.

## 6. `persist: true` on every association

**Why it hurts.** `persist: true` bakes the parent with `bake!` before the owner is validated, even under plain `bake`: an insert, a verification and a database dependency per edge. It also hides the one case that needs it. It is factory_bot's `strategy: :create` only in that sense, and most `strategy: :create` lines were habit.

**Instead.** Use it where a custom validator reads a parent's **id** (`user_id == invited_by_id` is `nil == nil` while unsaved), and where the old factory saved the parent (`author { create(:user) }`, `strategy: :create`). A required `belongs_to` and a raw-FK presence validator (`validates :user_id, presence: true`) need nothing: the plugin handles them.

```ruby
# bad
association :author, User, persist: true
association :category, Category, persist: true

# good: one line, with the reason
association :author, User, persist: true  # a validator compares author_id
```

## 7. `strategy: :fresh` everywhere

**Why it hurts.** `:fresh` is the default strategy, so the option is noise. It only changes behavior when the effective strategy is `:reuse_non_unique` (a global setting or an `Associations.with` scope).

**Instead.** Write it on the one edge where reuse could pick a row a custom rule forbids (Mastodon `PollVote`: reusing an account could pick the poll's own author). Leave the rest.

## 8. Memoizing a record across bakes

**Why it hurts.** A local declared **outside** `define` is shared by every bake. That is how a counter works, and it is why a cached record leaks. Under transactional tests the cached row is rolled back after the first example, so later examples hold an object whose row is gone *(reasoned, not run)*, and every test shares one mutable object, so results depend on order.

```ruby
# bad: one User for every bake
shared_user = nil
FactoryBakery.define(Post) do
  author { shared_user ||= FactoryBakery.bake!(User) }
end

# good: one per bake
FactoryBakery.define(Post) do
  association :author, User
end
```

To share a record between two blocks of one definition, read the sibling: declare it once and let the other block read it by name, so a call-site override is honored (`name { "#{user.name}'s account" }`). Do not capture it in a local from inside one block: if a test overrides the attribute, that block never runs and the local stays `nil`. Locals are for constants (`foo = 1`) and counters.

## 9. Relying on `:reuse_non_unique` for isolation

**Why it hurts.** It reads the database even under plain `bake` and takes the oldest matching row by primary key, so a test depends on data other tests or seeds left behind. It is a performance and row-count tool, not an isolation tool ([associations.md](../../../docs/guide/associations.md#strategies)).

**Instead.** Keep the default `:fresh` for isolation. Reuse only where a suite measured a gain, and use `:fresh` on edges with custom uniqueness rules.

## 10. Converting `build` to `bake!`

**Why it hurts.** `build` does not save. `bake!` saves, so validations raise, callbacks such as `after_create` and `after_commit` run, and row counts change. A test about an unsaved record fails or passes for a new reason.

```ruby
# bad
-  user = build(:user)
+  user = FactoryBakery.bake!(User)

# good
+  user = FactoryBakery.bake(User)
```

## 11. Copying a parent's lines into a subclass definition

**Why it hurts.** A class with no definition uses the nearest ancestor class's definition, traits included. An STI subclass often needs nothing: `bake!(Admin)` with `Admin < User` already uses `User`'s definition. A subclass definition **replaces** it entirely (definitions do not merge), so a copy drifts from the original, and a half-copy silently loses lines and traits.

This applies in Phase 7. In the 1:1 step (Phase 3) a `parent:`/nested subclass factory with its own body is translated with the parent's lines copied in, and a bare `class:` factory keeps only its own lines (an exact `define`, even an empty one — a bare `class:` inherits nothing in factory_bot). For the bare `class:` case, keep the exact definition in Phase 7 while `define(User)` keeps a line: without it `bake!(Admin)` inherits lines `create(:admin)` never had. Remove it in Phase 7 only when the effective ancestor's reduced definition reproduces it for every used call; an empty ancestor alone is not enough.

```ruby
# factory_bot
factory :admin, parent: :user, class: 'Admin' do ... end

# bad: a second definition that only repeats the parent's lines
FactoryBakery.define(Admin) { name { 'x' }; email { 'y' } }

# good: nothing. bake!(Admin) uses User's definition. (An empty exact
# definition is NOT this: it would shadow User's definition and lose
# the parent's lines.)

# when one is needed, it carries every line: the parent's kept lines (name, email)
# plus the subclass's own (role)
FactoryBakery.define(Admin) { name { 'x' }; email { 'y' }; role { 'admin' } }

# different factory_bot shape: `class: 'Admin'` with no parent:. There
# bake!(Admin) would inherit define(User), so register the exact definition
# on purpose — even an empty one shadows the ancestor definition
FactoryBakery.define(Admin) do
end
```

The call site stays a rename (`create(:admin)` to `FactoryBakery.bake!(Admin)`), so a differing value has to live in the definition. Do not add a call-site argument to carry it.

## 12. Deleting the old factories automatically

**Why it hurts.** Deleting factories, fixtures and the gem is the last one-way door. Seeds, rake tasks and other branches may still call them, and a deletion mixed into other commits cannot be reverted cleanly.

**Instead.** Ask last. Delete only on an explicit "delete", in one separate commit, after searching for remaining uses ([doors.md](doors.md#the-last-door-old-factories)). Silence means keep.

## 13. A big-bang rewrite

**Why it hurts.** One commit that changes every definition and call site cannot be bisected or reverted in part, and a failing suite gives no hint which model caused it.

**Instead.** Translate definitions in batches, rename call sites in batches, one commit each, the suite and the rename check after every batch.

## 14. `git reset --hard` or history rewrites

**Why it hurts.** It destroys the revert path the migration relies on, and in a main checkout it can destroy the user's uncommitted work.

**Instead.** Undo with `git revert` of the batch commit. Abandon the migration by removing the worktree and deleting its branch ([verification.md](verification.md#6-rollback)). Never force-push.

## 15. Expecting the gem to pick a value a custom validator accepts

**Why it hurts.** When a custom validator rejects a generated enum member, inclusion member, boolean or STI type, FactoryBakery does not search other values. Which value to use is a domain decision ([ADR-0008](../../../docs/adr/0008-user-chooses-domain-values.md)). Dropping the factory line that set it during the reduce step makes the model fail on some seeds.

```ruby
# bad: the factory_bot line was dropped as "covered by inference"
# FactoryBakery.bake!(WebHook)  # fails on some seeds

# good: the line stays, with its reason
FactoryBakery.define(WebHook) do
  wildcard_web_hook { true } # a custom validator rejects the generated value
end
```

On a failure, the `bake!` error and `FactoryBakery.explain(record)` print a definition snippet naming the attribute. See [`factory-bakery-diagnostics`](../../factory-bakery-diagnostics/SKILL.md).

## 16. Dropping a definition line on one green doctor run

**Why it hurts.** A value drawn at random can pass on one seed and fail on another, and doctor bakes each model only twice. One green run after a drop proves little, and the model's own tests may depend on the dropped value.

**Instead.** After each drop, re-run the tests that bake that model, and run doctor for it under three seeds. If any run fails, restore the line and record why.

```sh
for s in 1 2 3; do FACTORY_BAKERY_SEED=$s RAILS_ENV=test bin/rails 'factory_bakery:doctor[Post]'; done
```
