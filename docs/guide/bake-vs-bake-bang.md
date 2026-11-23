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
| Required-only fallback | A savepoint is opened so the lean attempt can be rolled back. Nothing remains. |

If your tests run inside a transaction, rows from these cases roll back with it.

## `bake!`: build, save, verify

`bake!` runs these steps inside one transaction opened with `requires_new`. Inside your own transaction that is a savepoint.

1. Build the graph (nested `bake!` calls from declaration blocks included).
2. Check that no record in the graph is read-only. A read-only record raises `FactoryBakery::ReadOnlyTargetError`. See [read-only targets](associations.md#read-only-targets).
3. Call `save!` on the root. ActiveRecord autosaves parents and children.
4. Run work that waits for the owner to be saved (for example optional `has_one` children under `:all`).
5. Verify that every record the bake generated reached the database.

If any step raises, every row the bake wrote is rolled back, even when you rescue the error inside an outer transaction.

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

A nested `bake!` (from `persist: true` or a declaration block) verifies only the records of its own build. An unsaved sibling of the same class, auto-built by the outer bake, is not its concern. See the [sibling case](../../skills/factory-bakery-diagnostics/references/diagnostics.md#nested-bake-sibling-of-same-class).

### Read-only models

`bake` fills a read-only model (a database view) and returns it unsaved. `bake!` refuses before any write:

```
Instance is read-only (readonly? is true, e.g. a database view); use FactoryBakery.bake to get a populated record, or create the underlying rows yourself. A persist_with hook is not supported yet.
```

### Models without ActiveRecord

If no mapper claims the class, `bake!` is `bake` plus `save!` when the object responds to it, with no transaction. Sequel models get `db.transaction(savepoint: true)` and Sequel's `save`. See [Sequel and ActiveModel](sequel-and-activemodel.md).

## Things that surprise people

- A block passed to `bake!` runs once, after the record is saved and verified, and receives the record: `FactoryBakery.bake!(User) { |u| u.admin! }`. A block passed to `bake` receives the unsaved record.
- `bake!` returns the object with in-memory state. Call `reload` if a test needs database state.
- Depth is capped. Nested bakes deeper than `FactoryBakery.max_bake_depth` (default 10) raise `FactoryBakery::NestingTooDeepError`:
  ```
  bake nesting exceeded max_bake_depth (2): User -> User -> User
  ```
- Declaration blocks can run twice when the verified fallback fires. See [Heuristics](heuristics.md#the-verified-fallback).
- Each bake keeps its own state per fiber, so threads do not share a graph.
