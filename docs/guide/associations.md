# Associations

Core never invents relationship values. The opt-in **associations plugin** builds associated records when you ask for it. Design: [ADR-0003](../adr/0003-associations-opt-in-plugin-bounded-modes.md), [ADR-0007](../adr/0007-reuse-only-non-unique-edges.md).

## Without the plugin

Heuristics cannot know which row a foreign key should point to. Core leaves these `nil`:

- `belongs_to` foreign keys (every part of a composite one)
- polymorphic `*_type` / `*_id` pairs
- the STI discriminator and counter caches

You can still assign an association by hand, lazily:

```ruby
FactoryBakery.define(Comment) do
  post { FactoryBakery.bake(Post) }   # an unsaved Post; `bake` does not write
end
```

`post { nil }` (or `comments { [] }`) in a trait or at the call site opts an edge out.

Using `association :x` without the plugin raises:

```
`association` requires the associations plugin: require 'factory_bakery/associations'
```

## Loading the plugin

Outside Rails:

```ruby
require 'factory_bakery/associations'
```

In Rails, set it in `config/application.rb` or an environment file. The Railtie loads and configures the plugin **before** definition files, so definitions can use `association`:

```ruby
config.factory_bakery.associations = { mode: :required_only }  # omitted keys keep defaults
# config.factory_bakery.associations = true                    # all defaults
# config.factory_bakery.associations = :all                    # a bare mode symbol
# unset or false: core behavior
```

Accepted keys: `mode`, `strategy`, `max_depth`, `default_count`, `eager_load`. Unknown keys and invalid values raise `ArgumentError`.

Note that once the plugin is loaded, the default mode is `:required_only`. The mode `:none` turns auto-building off while keeping the DSL.

## Modes

| Mode | Auto-builds (unless declared or overridden) | Never auto-builds |
| --- | --- | --- |
| `:none` | Nothing. Only explicit `association` declarations | Everything else |
| `:required_only` (default) | Required `belongs_to`, recursively. A direct `has_one` whose presence validator applies to the owner | Optional `belongs_to`, other `has_one`, `has_many`, through, HABTM, optional polymorphic |
| `:all` | Every non-polymorphic `belongs_to` (optional too), every `has_one` (one child), every `has_many` (`default_count` children) | Through, HABTM, optional polymorphic |

"Required" means one of: a presence validator on the association name (conditions and `on: :create` honored), a presence validator on the raw foreign key column, or a `NOT NULL` foreign key. Plain ActiveRecord outside Rails defaults `belongs_to` to optional, so a spec model that means "required" must say `optional: false`.

```ruby
FactoryBakery.bake(Comment)  # :required_only builds the required post, unsaved
```

### `:all` stays bounded

- **It never walks back the edge it came from.** A child of `post.comments` is bound to that post and does not grow a second post.
- **`max_depth` (default 2) truncates `:all` to required-only.** It does not raise. The root bake is depth 1.
- **In-graph identity.** An auto-built `belongs_to` reuses an object of exactly the target class already completed in this bake, so `comment.user` and `comment.post.user` are one record. Not shared: scoped or polymorphic edges, an owner foreign key with uniqueness, two edges of one owner (`transfer.sender` and `transfer.receiver`), and under `bake!` any parent not yet persisted.
- **Optional edges are best effort.** Each is built in a savepoint. If the child raises or is invalid (or its unsaved required parents are), the edge stays `nil` or empty.
- **Cycles stop at required edges.** An optional edge that would repeat its path, or point at a class being built, is left `nil`.
- **HABTM plumbing is skipped**, and so are `has_many` edges whose foreign key is not a column of the target (dead associations).
- **Unwired back-references are skipped.** A `has_many`/`has_one` with no verified inverse, whose child has a required `belongs_to` back, is not built.
- Read-only optional children are discarded, not failed.

```ruby
FactoryBakery::Associations.with(mode: :all, default_count: 3) do
  FactoryBakery.bake!(Post) # direct associations plus three comments
end
```

### `has_one`

A direct `has_one` is auto-built only when a presence validator on the **association name** applies to the owner. Conditions are checked on the owner after declarations are assigned, so `unless: :skip_email_validation` suppresses the child. The child is built through the association, so its create scope, foreign key and inverse apply first. `has_one :through` is never auto-built.

A has_one created by an owner callback (`after_create :create_profile`) can collide with a gem-built child. The gem handles this for its automatic children: under `bake!` it waits until the owner is saved and keeps the callback's row. A has_one you declare yourself gets no such handling (read from the code, not run): drop the declaration or `skip` the edge.

## The `association` DSL

```ruby
association(name, [TargetClass], *traits, factory: nil, strategy: nil, count: nil, persist: false, with: {}, &owner_block)
```

```ruby
FactoryBakery.define(Post) do
  association :author                                          # reflection class, its definition and inference
  association :category, :featured, with: { name: 'News' }     # trait, and overrides for the child
  association :editor, AdminUser                               # target class, same as factory: AdminUser
  association :editor, factory: :admin_user                    # named factory
  association :commentable, Post                               # polymorphic: the class is required
  association :comments, count: 3, with: { body: 'nice' }      # has_many: three children bound to this post
  association :cover                                           # has_one: one child bound to the owner
  association :topic, persist: true                            # belongs_to saved first
  association(:reviewer) { |post| FactoryBakery.bake(User, team: post.team) }
end
```

| Option | Meaning |
| --- | --- |
| `name` | The association name. Checked at **bake time**, not definition time. A typo raises `FactoryBakery::Error`: `Post has no association :nope` |
| positional class | Same as `factory:`. Traits are always symbols, so a Class is unambiguous. Giving both raises `pass the target class positionally or as factory:, not both` |
| `*traits` | Passed to the child's bake, in order |
| `factory:` | A registered symbol, or a class compatible with the reflection (a subclass is fine). Mandatory for polymorphic declarations |
| `strategy:` | `:fresh` or `:reuse_non_unique`. `belongs_to` only |
| `count:` | Non-negative Integer, collections only. `0` builds an empty, loaded collection. Default 1 |
| `persist:` | `true` saves a `belongs_to` target first. See below |
| `with:` | Hash of overrides for the child |
| block | Receives the owner (all plain attributes assigned) and its whole return value is assigned |

### `with:`

Overrides for the child are kept apart from the options, so a column named `count` or `strategy` can still be set. An override passed beside the options raises:

```
unknown association option(s) name:; pass attribute overrides as with: {name: "x"}
```

`with:` must be a Hash: `with: must be a Hash of attribute overrides`.

### persist

`persist: true` bakes a `belongs_to` target with `bake!`. The target and its graph are saved and verified before the owner is validated, even under plain `bake`. It is factory_bot's `strategy: :create` on an association.

Use it when a validator reads the parent's **id**, not the object. While the parent is unsaved its id is `nil`, so `user_id == invited_by_id` is `nil == nil`:

```ruby
class Invite < ApplicationRecord
  belongs_to :user
  belongs_to :invited_by, class_name: 'User'
  validate { errors.add(:base, 'inviter must differ') if user_id == invited_by_id }
end

FactoryBakery.define(Invite) do
  association :user, persist: true
end
```

Rules:

- Refused on `has_one` / `has_many` (a child needs the owner's id): `persist: is only supported on belongs_to, but X#y is a has_many association`.
- Refused with a block: `a block cannot be combined with persist:; call bake! inside the block`.
- `persist:` must be `true` or `false`.

A nested `bake!` verifies the graph it builds. Two edges can target the same class while using different persistence options. In this example, plain `bake` can leave `invited_by` unsaved, and an enclosing `bake!` verifies both parents after it saves the invite.

### Owner block

The block gets the owner. Use it when the child depends on another value of the owner:

```ruby
association(:reviewer) { |post| FactoryBakery.bake(User, team: post.team) }
association(:status) { |filter_status| FactoryBakery.bake!(Status, account: filter_status.custom_filter.account) }
```

A block cannot be combined with `count:`, traits, `factory:` or `with:`: `a block cannot be combined with count:, traits, factory: or with:`.

### Children are built through the association

A `has_many`/`has_one` child gets the association's create scope (foreign key, polymorphic type, scope attributes) and its verified inverse **before** its own inference runs. `bake!` persists the whole graph. `has_many :through` and HABTM raise:

```
X#y (has_many) is not supported; assign via an attribute block
```

A declared collection block that bakes its own children must pass the owner, or each child builds its own required parent and the result cycles:

```ruby
association(:articles) { |cat| [FactoryBakery.bake(Article, title: 'x', cat: cat)] }
```

### Literal overrides apply to every child

`association :items, count: 2, with: { label: 'same' }` gives both children the same `label`. If `label` has a uniqueness validator the owner is invalid (`Validation failed: Items is invalid`). FactoryBakery does not make a literal unique. Leave the value to inference, or build the collection in a block with distinct values.

### Precedence

> call-site overrides > traits > declarations > plugin auto-build > heuristics

A call-site override of `author` **or** `author_id` suppresses both the declaration and auto-building for that edge.

## Strategies

| Strategy | Behavior |
| --- | --- |
| `:fresh` (default) | Every edge bakes a new target. Unsaved under `bake`, inserted by autosave under `bake!` |
| `:reuse_non_unique` | A `belongs_to` takes an existing row **only when the edge cannot be unique**. Otherwise it builds fresh |

For `:reuse_non_unique`, lookup order is: a completed matching object in this bake, then the database (exact STI class, association scope and scalar overrides; oldest row by primary key), then a fresh build.

An edge counts as **unique** (and builds fresh, skipping both lookups, and the object is not remembered for reuse) when:

- the owner has a uniqueness validator or a unique index (single or composite) containing the edge's foreign key, or
- the target's inverse is a `has_one`.

```ruby
association :category, strategy: :reuse_non_unique
```

Setting order, most specific first: per-association `strategy:`, then `Associations.with(strategy:)`, then `Associations.strategy = :fresh`.

Limits:

- `belongs_to` only. An **explicit** setting on a collection raises (`strategy: :reuse_non_unique is only supported on belongs_to, but ...`). An inherited setting quietly skips ineligible edges.
- Traits plus `:reuse_non_unique` on a `belongs_to` raise.
- Only scalar, column-backed overrides are matched. Others force a fresh build. Encrypted or serialized overrides and a missing or composite primary key raise `ArgumentError`.
- It **reads the database even under `bake`**, so it ties tests to existing data. On MySQL, string matches can be case-insensitive.
- Uniqueness only enforced in a custom validator or callback is invisible. Such an edge is still reused. Use `strategy: :fresh` on it, or declare it. (Mastodon's `PollVote`: reusing an account could pick the poll's own author.)

`:reuse` was renamed to `:reuse_non_unique` with no alias. `strategy: :reuse` raises `invalid associations strategy :reuse; expected one of [:fresh, :reuse_non_unique]`.

## Polymorphic edges

A required polymorphic `belongs_to` with no declaration discovers its target:

1. **Inclusion validator on the `*_type` column**: `validates :votable_type, inclusion: { in: %w[Post PostVotingComment] }`. Each listed name that resolves counts. Constants work (`in: SUPPORTED_LINKABLE_TYPES`). A candidate's `polymorphic_name` must be in the list, and several unconditional domains are intersected.
2. **Inverse `as:` reflections on loaded models** whose `class_name` matches the class being baked (an ancestor or descendant counts).
3. **One `Rails.application.eager_load!` per process**, only when the first two found nothing, then a second inverse scan.

A database foreign key constraint on the `*_id` column narrows the candidates to classes stored in the referenced table (Doorkeeper's `owner_id` references `users`, so `Account` is never picked). When no source found a candidate, the single model stored in that table is used.

Candidates are ordered: non-abstract first, then classes whose table exists, then by name. The first that bakes cleanly wins. The result is cached per (class, association).

A non-polymorphic `belongs_to` whose `class_name` has no constant is resolved the same way: first through the owner's `polymorphic_class_for` mapping, then through the foreign key constraint on its column. The foreign key column is assigned directly. Without either, the original `NameError` surfaces.

Disable the eager load when your tests manage loading:

```ruby
FactoryBakery::Associations.eager_load = false
FactoryBakery::Associations.with(eager_load: false) { FactoryBakery.bake(Note) }
```

When nothing is discovered:

```
Note#noteable is a required polymorphic association; no target discovered from: inclusion validator on noteable_type; inverse as: reflections on loaded models; Rails.application.eager_load! (disabled by config). Declare it (e.g. association :noteable, factory: SomeClass) or pass noteable: to name its target
```

Declaring `association :noteable, Topic` (verified), passing `noteable:` or `skip :noteable` all suppress discovery. A declared polymorphic edge without a class raises `Note has a polymorphic association :noteable; pass factory: to name its target class`.

## Natural-key `belongs_to`

A `belongs_to` with a `primary_key:` other than `id` (`foreign_key: :domain, primary_key: :domain`) is **data**, not a reference to a generated id. Its foreign key is filled by heuristics. An optional natural-key edge leaves the association unset and the record valid.

When the edge is required (presence validator on the association), the parent is built **after** the child's key is known. The value (override, declaration or inference) is passed to the parent as its key. Parent and child agree. `:none` never builds these parents.

## Raw-FK presence parents

`validates :user_id, presence: true` validates the column. An unsaved parent has a `nil` id, so the foreign key stays `nil` and the record is invalid. For this one case the plugin gives the parent a real id before validation:

| Call | Behavior |
| --- | --- |
| `bake!` | Creates the parent inside the root savepoint and sets the FK. It rolls back with the graph when `FactoryBakery.savepoints = true`; with the default off the row stays |
| `bake` (`:fresh`) | Creates the parent and **inserts a row**. This is the documented exception to "`bake` writes nothing". The root stays unsaved |
| `bake`, `:reuse_non_unique` | An existing row is reused without a write when the edge cannot be unique. On a miss, or a unique edge, the parent is inserted as with `:fresh` |
| `bake!`, `:reuse_non_unique` | Existing row if possible, else a fresh parent inside the savepoint |

An association-presence edge (`validates :user, presence: true`) is unaffected: the parent stays unsaved. An explicit `user:` or `user_id:` at the call site skips all of this. A broken grandparent raises `X cannot be inserted: its required Y is invalid (...)`.

## Cycles and depth

A required cycle (a mutual required `belongs_to`, a required self-reference) raises `FactoryBakery::CyclicAssociationError`:

```
Node#parent -> Node#parent; declare one side (e.g. parent { nil }) or make it optional
```

`inverse_of` does not make an insert cycle persistable. Break the loop by declaring one side or making it optional. A finite chain ended by a declaration works. An acyclic chain deeper than `FactoryBakery.max_bake_depth` (default 10) raises `NestingTooDeepError`.

## Read-only targets

A model with `readonly?` true (a database view) is a valid `bake` target. `bake!` refuses before any write (`ReadOnlyTargetError`, [message](bake-vs-bake-bang.md#read-only-models)). When a read-only record is a required parent, the error names the chain, for example `InstanceModerationNote#instance -> Instance is read-only (...)`.

- On a raw-FK presence edge, the parent is **never written**. The plugin adopts an existing row of that class. With an empty table, `bake` returns the child with the unsaved parent and `bake!` raises.
- Under `bake!`, a read-only `belongs_to` parent is never autosaved on any edge. An existing row is adopted, or the bake raises.
- Under `bake`, a read-only parent on a non-FK edge stays unsaved and populated, with no database read.
- Workaround for a view: `skip :instance` and set the natural key (`domain { 'example.com' }`), or create the rows yourself.

## Settings and scoping

```ruby
FactoryBakery::Associations.mode          = :required_only  # :none | :required_only | :all
FactoryBakery::Associations.strategy      = :fresh          # :fresh | :reuse_non_unique
FactoryBakery::Associations.max_depth     = 2               # non-negative Integer
FactoryBakery::Associations.default_count = 1               # non-negative Integer
FactoryBakery::Associations.eager_load    = true            # true | false
```

Readers return the **effective** value (scoped override, else global). `Associations.with(**settings) { ... }` overrides for one block: it covers nested bakes, is fiber-local, nests (inner wins), restores on error and returns the block's value. Unknown keys raise `unknown associations scope option :foo; expected one of [:mode, :strategy, :max_depth, :default_count, :eager_load]`. `with` is a block, not a `bake` keyword, because bake keywords share a namespace with column names.

For test isolation: `FactoryBakery::Associations.reset_configuration!`.

## Associations and Sequel

Sequel `many_to_one` foreign keys stay `nil`. The DSL raises `no associations on Book; it is not ActiveRecord` (verified). Assign associated objects in an attribute block. See [Sequel and ActiveModel](sequel-and-activemodel.md).
