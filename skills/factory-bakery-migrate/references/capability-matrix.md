# Capability matrix

Everything a factory_bot (or similar) factory can express, sorted into three classes. Each row has the reason. Verified against the code on `v0.0.2`. Rows marked *(not run)* were read from the code, not exercised.

- **Automatic**: inference or the associations plugin handles it. Write nothing. Drop the old line.
- **Needs a definition**: FactoryBakery can do it, but you must say so in a definition (or association option).
- **Not supported**: no equivalent. Solve with a helper that keeps test diffs to renames, or report as a **blocker**.

Rule for every row: a test that **asserts on** the value, or looks the record up by it, keeps a definition line, whatever the class.

## Automatic: can be handled with no definition

| Capability | Reason |
| --- | --- |
| String, integer, float, decimal, boolean, date, datetime, time, JSON columns | A filler per normalized column type |
| `NOT NULL` column with no default | Filled by the required-attribute rule |
| `presence`, `absence` validators | Filled with a non-blank value, or `nil` |
| `inclusion`, `exclusion` | A value inside, or outside, the set |
| `length` (`is`, `in`, `minimum`, `maximum`) | The value is padded or cut to fit |
| `numericality`, `comparison`, `other_than`, `even/odd`, Proc and Symbol bounds | A number inside the bounds, resolved at bake time |
| `format: { with: }` | Generated from the regex itself, then verified. Bounded |
| `acceptance`, `confirmation` | The accepted value. The twin copies the source |
| Rails `enum` (including on `alias_attribute`) | A defined key |
| Column defaults | Kept, unless blank and presence-validated |
| `uniqueness` and single-column unique indexes | Regenerated on a collision, in the database and across one bake graph |
| Conditional validators (`if:` / `unless:`) | Evaluated against the record being baked |
| `has_secure_password` and other validated virtual attributes | Filled when a validator rejects `nil`. The confirmation is matched |
| Name-shaped strings (title, body, url, email, host, ip, timezone, filename) | A name-rule table, with reserved domains and IPs |
| Name-, slug-, key-, label-like strings staying distinct | A six-digit suffix |
| Required `belongs_to` | Plugin, `:required_only` |
| Required `has_one` (presence validator on the association) | Plugin, `:required_only` |
| Optional `belongs_to`, `has_one`, `has_many` | Plugin, `:all` only |
| Polymorphic `belongs_to` with an `inclusion` list on the type column, or `as:` inverses | Target discovery |
| Natural-key `belongs_to` (`primary_key:` not `id`) | The parent is built with the child's key |
| Raw-FK presence (`validates :user_id, presence: true`) | The plugin inserts the parent first |
| `has_many`/`has_one` ownership wiring (FK, inverse) | Built through the association |
| Diamond graphs (`comment.user` is `comment.post.user`) | In-graph identity |
| Required file attachments (Active Storage `has_one_attached`, Paperclip) | Attachments plugin, bundled fixtures |
| STI | The `type` column is left to Rails. Bake the subclass |
| Counter caches | Left to Rails (`0` for NOT NULL with no default) |
| Text columns cast to JSON by an index | A JSON object string |
| Models whose `new` raises | `unscoped` then callback-free construction |
| Read-only models under `bake` | Populated, unsaved |
| Atomic `bake!` and rollback | One savepoint transaction |
| Persistence verification | `IncompletePersistenceError` for a half-saved graph |
| Cycle detection and depth backstop | `CyclicAssociationError`, `NestingTooDeepError` |
| `FactoryBot.lint` | `factory_bakery:doctor` (Rails, gem version with the rake tasks). It checks models, not named factories or traits |

## Needs a definition

| Capability | What to write | Reason |
| --- | --- | --- |
| A test asserts on an exact value | `attr { 'value' }` | Inference is random |
| Specific state (`:published`, `:admin`) | `trait` | A state is a test decision |
| Registry, provider list, site setting, emoji list | A block returning a registry value | Not a discoverable constraint ([ADR-0004](../../../docs/adr/0004-extend-generation-within-discoverable-constraints.md)) |
| Custom validator that needs particular values | One block per needed attribute | Unreadable logic |
| Time-relative custom validation | A block computing from "now" | Custom code |
| Structured JSON/YAML in a **text** column (not index-cast) | A block returning the shape | No schema to read |
| Cross-record rule (a follow must exist) | A block that bakes the related record | App-specific setup |
| Validator reads a parent's **id** | `association :x, persist: true` | Unsaved parents have nil ids |
| Reuse picks the owner's own parent | `strategy: :fresh` | The rule is in a custom validator the gem cannot see |
| Literal child values under uniqueness | A block with distinct values, or leave to inference | Literals are not regenerated |
| Side-effecting setter | `skip :attr` | Heuristics must not call it |
| Read-only view as a parent | `skip :edge` and set the natural key | A view cannot be inserted |
| Cycle under `:all` | `skip :edge` or `edge { nil }` | Required cycles raise |
| Owner callback creates the has_one | Remove your declaration, or `skip` | Both would insert the row |
| Abstract STI base | `initialize_with(type: 'Sub')` or `define(:x, klass: Sub)` | The subclass is not discoverable |
| Polymorphic without an inclusion list or loaded inverse | `association :x, Klass` | Nothing to discover |
| `has_many :through`, HABTM | An attribute block | `association` refuses them |
| Several has_many children | `association :x, count: n` | One child by default |
| `class: 'Ns::Model'` or a factory name differing from the class | `define(:name, klass: Ns::Model)` | Names resolve by camelizing |
| Factory inheritance (`parent:`, nested `factory`) | A trait, or a second definition | No inheritance |
| `aliases:` | A second `define(:alias, klass: X, &same_block)` | One key per `define` |
| `sequence` | A counter local at the top of the file | There is no `sequence` DSL |
| `transient` used only inside the factory | A local inside `define` | Locals are fresh per bake |
| `association :x, strategy: :create` | `association :x, persist: true` | Same intent |
| `initialize_with { ... }` that builds from a simple hash | `initialize_with(a: 1)` | A Hash only |
| DB-only constraint (check constraint, composite unique index, trigger) | A block giving an accepted value | Not visible to the mapper |
| A regex the generator cannot satisfy | A literal or generator block | Bounded generator |
| Enum or inclusion lists held in a constant (non-polymorphic) | Usually automatic. If a custom validator also restricts it, a block | Custom rule |
| `before(:create)`-like work that only prepares **records** | A block that bakes them (`association` with a block) | Done during the build |

## Not supported: helper or blocker

| Capability | Why | What to do |
| --- | --- | --- |
| `build_stubbed` | No stubbed-persisted object. `bake` returns `persisted? == false`, `id == nil` | **Blocker.** Report |
| `build_stubbed_list` | Same | Blocker |
| `attributes_for` | No built-in | A thin helper that keeps call sites a rename ([testing recipes](../../../docs/guide/testing-recipes.md#attribute-hash-for-a-request-spec)). Its keys are strings and it omits associations. If a test needs symbol keys or associations, blocker |
| Transient attributes as **call-site parameters** (`create(:user, with_posts: 3)`) | No transient DSL | Blocker. A trait or `association :posts, count: 3` may replace a specific use, but the call changes |
| `after(:build)`, `after(:create)`, `before(:create)`, `callback` | No definition callback DSL | Report hooks that must run for every call. Individual calls can pass a block to `bake` or `bake!` |
| `initialize_with { ... }` block with logic | A Hash only | Hash if simple. Otherwise blocker |
| `FactoryBot.generate(:seq)`, global sequences | No sequence registry | Helper with a counter, or blocker |
| Trait that applies another trait | A trait cannot call a trait | Repeat the lines, or pass both traits at the call site (call changes: blocker if many) |
| Nested attributes via `traits_for_enum` | Not a feature | Automatic enum inference, or explicit traits |
| `to_create`, `skip_create` customizing save | `bake!` calls `save!` | Blocker if a test depends on it |
| `FactoryBot.create` in seeds or rake tasks | Not a test file | Out of scope. Report |
| Rails fixtures (`users(:ada)`) | Named global data. A conversion changes tests | Not converted. Report |
| Sequel associations | Never auto-built | An attribute block |
| `stub_method` (temporary stubbing of a callback during a bake) | Proposed, not shipped (engineering log, section 8) | Blocker |
| A different ORM (Mongoid, ROM) | No mapper | Out of scope |
| Per-example override of a factory | `define` is global | Use a call-site override |

## Reading the matrix

1. Find the row. Take the class it names.
2. **Automatic**: delete the old line (after the user agrees to simplify).
3. **Needs a definition**: write that one line and name the reason in a comment only when it is not obvious.
4. **Not supported**: do not touch the test. Report the file, line and reason.
