# `bake` vs `bake!`

| | `FactoryBakery.bake` | `FactoryBakery.bake!` |
| --- | --- | --- |
| Returns | The object, **unsaved** | The object, **saved**, after the whole graph is verified |
| Writes to the database | Nothing of its own (exceptions below) | The whole graph, in one transaction |
| Validates | Only when needed to verify a lean bake (see [Heuristics](heuristics.md#the-verified-fallback)) | Through `save!` |
| On an invalid record | Returns it. You check `valid?` | Raises (`ActiveRecord::RecordInvalid`) and rolls back |
| Target without `save!` (a PORO) | Returns the object | Returns the object, nothing saved |

Both take the same arguments: a class or registered symbol, any number of traits, then override keywords.

```ruby
FactoryBakery.bake(Post, :published, title: 'Hello')
FactoryBakery.bake!(Post, :published, title: 'Hello')
```

## `bake`: build only

`bake` calls `new`, assigns values and returns. It never calls `save!` on the root.

`bake` does not check that the result is valid. It checks only when it has a reason to (a column with a default that a validator constrains, or validation logic the gem cannot read). If the record is invalid and the fallback cannot fix it, you get the invalid record back. This is how you test validations:

```ruby
user = FactoryBakery.bake(User, email: 'not-an-email')
user.valid?               # => false
user.errors.full_messages # => ["Email is invalid"]
```

### When `bake` still writes

These are documented exceptions. Everything else in a `bake` is database-free.

| Case | What is written |
| --- | --- |
| A [raw-FK presence edge](associations.md#raw-fk-presence-parents) (`validates :user_id, presence: true`) | The parent row is inserted, outside any transaction of its own. The root stays unsaved. |
| `association :x, persist: true` | The target and its graph are saved with a nested `bake!`. |
| A declaration block that calls `bake!` or `create!` | Whatever the block saves. |
| `strategy: :reuse_non_unique` | No write, but it **reads** the database and takes an existing row. |
| Required-only fallback | With `savepoints = true` the lean attempt's rows are rolled back, so one copy remains; with the default they stay behind. See [Savepoints](#savepoints) |

If your tests run inside a transaction, rows from these cases roll back with it.

## Savepoints

`FactoryBakery.savepoints` (default `false`) decides whether the gem wraps its persistence in a nested transaction, which is a savepoint when your code already has a transaction: the `bake!` envelope, and the verified fallback's attempts. The default matches factory_bot: the gem opens none, so the cost is gone, and a failure leaves whatever `save!` already wrote. Turn it on for atomic `bake!`:

```ruby
FactoryBakery.savepoints = true # or config.factory_bakery.savepoints = true in Rails
```

| | `savepoints = false` (default) | `savepoints = true` |
| --- | --- | --- |
| `bake!` fails (invalid root, `IncompletePersistenceError`, `ReadOnlyTargetError`) | `save!` rolls back its own rows. Parents a declaration block or an FK-presence edge saved earlier stay | Every row the bake wrote is rolled back |
| Verified fallback rebuild | The lean attempt's rows stay behind, so a declaration-block parent can exist twice | The lean attempt's rows are rolled back, so one copy remains |
| Optional edges (`:all`) and polymorphic candidates that fail | Rolled back with the attempt, always | Same |

The fallback trade-off with the default: its rebuild re-runs declaration blocks, so a block that saves a parent with a unique value (for example `account { FactoryBakery.bake!(account, name: 'acme') }` with a unique `name`) fails the rebuild with "has already been taken" against the row the lean attempt left behind. `FactoryBakery.savepoints = true` fixes it by rolling the lean attempt's rows back. A savepoint is lazy — it sends SQL only when a query runs inside it — so it costs almost nothing.

The associations plugin's best-effort edges keep their savepoints either way: they rescue a failed child and carry on, and on PostgreSQL a failed statement outside a savepoint would abort the whole transaction. And one more case to know with savepoints off: `save!` joins a caller's own transaction, so after a database error rescued inside that transaction PostgreSQL aborts it. Transactional tests are unaffected.

Inside a transactional test none of this is visible: the test's own rollback removes every row.

## `bake!`: build, save, verify

`bake!` runs these steps inside one transaction opened with `requires_new` when [savepoints](#savepoints) are on. Inside your own transaction that is a savepoint.

1. Build the graph (nested `bake!` calls from declaration blocks included).
2. Check that no record in the graph is read-only. A read-only record raises `FactoryBakery::ReadOnlyTargetError`. See [read-only targets](associations.md#read-only-targets).
3. Call `save!` on the root. ActiveRecord autosaves parents and children.
4. Run work that waits for the owner to be saved (for example optional `has_one` children under `:all`).
5. Verify that every record the bake generated reached the database.

If any step raises and savepoints are on, every row the bake wrote is rolled back, even when you rescue the error inside an outer transaction. With them off, only `save!`'s own transaction rolls back.

```ruby
ActiveRecord::Base.transaction do
  begin
    FactoryBakery.bake!(Item, label: nil, cat: nil) # raises NotNullViolation
  rescue ActiveRecord::StatementInvalid
    # no Item and no Cat row remains
  end
end
```

### The verification step

A record can stay unsaved even though the root saved. This happens with `autosave: false`, or `validate: false` on an invalid child. Handing that back would give you a half-saved graph, so `bake!` raises:

```
bake! did not persist all generated records: Member (assigned to members). Persist the record explicitly via a declaration or override, or change the association's autosave/validate options.
```

The error class is `FactoryBakery::IncompletePersistenceError`. The whole bake is rolled back first. See [diagnostics](../../skills/factory-bakery-diagnostics/references/diagnostics.md#incomplete-persistence).

Known limit (observed, not documented elsewhere): the check is scoped by the **class path** of the nested bake. If a nested `bake!(User)` runs (from `persist: true` or a declaration block) while a sibling edge of the same class `User` was auto-built and is still unsaved, the check sees that sibling and raises. Persist both edges, or declare the sibling. See the [sibling case](../../skills/factory-bakery-diagnostics/references/diagnostics.md#nested-bake-sibling-of-same-class).

### Read-only models

`bake` fills a read-only model (a database view) and returns it unsaved. `bake!` refuses before any write:

```
Instance is read-only (readonly? is true, e.g. a database view); use FactoryBakery.bake to get a populated record, or create the underlying rows yourself. A persist_with hook is not supported yet.
```

### Models without ActiveRecord

If no mapper claims the class, `bake!` is `bake` plus `save!` when the object responds to it, with no transaction. Sequel models get `db.transaction(savepoint: true)` and Sequel's `save`. See [Sequel and ActiveModel](sequel-and-activemodel.md).

## Things that surprise people

- A block passed to `bake!` is **ignored**. `FactoryBakery.bake!(User) { |u| u.admin! }` runs the block never. Do the work after the call.
- `bake!` returns the object with in-memory state. Call `reload` if a test needs database state.
- Depth is capped. Nested bakes deeper than `FactoryBakery.max_bake_depth` (default 10) raise `FactoryBakery::NestingTooDeepError`:
  ```
  bake nesting exceeded max_bake_depth (2): User -> User -> User
  ```
- Declaration blocks can run twice when the verified fallback fires. See [Heuristics](heuristics.md#the-verified-fallback).
- Each bake keeps its own state per fiber, so threads do not share a graph.
