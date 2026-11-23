# Heuristics

For every attribute that no override, trait or declaration decided, FactoryBakery picks a value generator. ActiveRecord models contribute column types and validators. Any ActiveModel-compatible object contributes validators. The generator reads the validator options and produces a value that passes them.

Design rule ([ADR-0002](../adr/0002-heuristic-first-verified-generation.md), [ADR-0004](../adr/0004-extend-generation-within-discoverable-constraints.md)): generation uses only *discoverable constraints*. App-specific rules belong in a [definition](definitions.md).

## What gets filled

A default bake fills only what a **valid record needs**. In order:

1. A validated attribute with no column (a `has_secure_password` `password`, an `attr_accessor` with presence, an acceptance flag, a confirmation twin) is filled when the model has a public setter and an applicable validator rejects `nil`. Acceptance and confirmation attributes are filled too.
2. A `NOT NULL` column with no default is filled.
3. A column with a **blank** default (`''`, `false`, whitespace) is filled when an applicable presence validator requires it. A non-blank default is kept.
4. A nullable column with no default is filled when an applicable validator rejects `nil`: `presence`, `inclusion`, `format`, `numericality`, `acceptance`, `uniqueness`, `comparison`, or `length` with `minimum > 0`. `allow_nil` and `allow_blank` relax this.

Everything else keeps its default or stays `nil`, and its setter is **never called**. That is deliberate: an optional `avatar_remote_url=` that downloads a file must not run during a test.

`if:` and `unless:` are evaluated against the record being baked, after declarations and overrides are assigned. So "applicable" means the condition holds for this record ([ADR-0005](../adr/0005-condition-aware-constraints.md)). Symbol and String method names, arity-0 and arity-1 procs, and arrays of them work. A condition that raises leaves its validator applicable.

Custom `EachValidator`s never force a fill on their own. See [the verified fallback](#the-verified-fallback).

### Example

```ruby
class User < ApplicationRecord
  validates :email, presence: true, uniqueness: true
  validates :role,  inclusion: { in: %w[member admin] }
  validates :bio,   length: { maximum: 10 }
end

user = FactoryBakery.bake(User)
user.email # filled: presence + uniqueness
user.role  # filled: inclusion rejects nil
user.bio   # nil: max length does not require a value
```

## What each source produces

| Source | Example | Result |
| --- | --- | --- |
| Column type | `:string`, `:integer`, `:datetime`, `:json` | A type-appropriate fake value (strings from FFaker) |
| `inclusion` | `in: %w[draft published]` | One member of the set |
| `exclusion` | `in: %w[www ftp]` | A value outside the set |
| `length` | `is: 5`, `in: 3..8`, `maximum:` | A string padded or cut to fit |
| `numericality`, `comparison` | `greater_than: 17`, `in: 1..10`, `other_than`, `even` | A number inside the bounds. Procs and symbols resolve at bake time |
| `format` | `with: /\A[a-z]+\z/` | A string generated **from the regex** (see below) |
| `acceptance` | `accept: 'yes'` | The accepted value |
| `confirmation` | on `password` | `password_confirmation` copies `password`, and follows an override of it |
| `presence` / `absence` | | A non-blank value, or `nil` |
| `enum` (including on `alias_attribute`) | `enum status: { pending: 0, done: 1 }` | One defined key |
| Column default | `default: 'draft'` | The default is kept, unless it is blank and presence-validated |
| Single-column unique index | `add_index :users, :code, unique: true` | Treated as a uniqueness rule |
| JSON column | `json`, `jsonb`, default `[]` | A Hash, or an Array when the default or serializer says so |
| Text column cast to JSON by an index (`col::jsonb`) | Discourse `notifications.data` | A JSON object string |
| Array-typed text (`serialize :tags, type: Array`) | | An Array |
| No information | nullable column, no validator | `nil` |

### Strings by name

When the attribute name says what it holds, the value has that shape. All hosts, URLs and IPs are reserved test values (RFC 2606, RFC 5737).

| Name | Shape |
| --- | --- |
| `title`, `subject`, `headline` | 4-8 words, at least 20 characters |
| `body`, `raw`, `content`, `description`, `message`, `text` | A paragraph, at least 60 characters |
| `url`, `*_url`, `website`, `endpoint`, `uri`, `link` | `https://` on `example.com`, `example.test` or similar |
| `filename`, `file_name` | `<word>.png` |
| `host`, `hostname`, `domain` | `<word>.example.com` |
| `ip`, `ip_address`, `inet` column | `192.0.2.<n>`; `cidr` gets `192.0.2.0/24` |
| `timezone`, `time_zone` | `UTC` or a real IANA zone |
| `email` | A plausible address |

Name-, title-, slug-, key- and label-like strings end in a six-digit suffix (`"Voluptas 482193"`), so values your app derives from them (a slug from a name) stay distinct. Emails, `username`-style identifiers and declared formats are not suffixed.

### Format validators

`format: { with: regex }` is generated by walking the regex's syntax tree (via `regexp_parser`). The value is built from the pattern. It is not guessed and filtered.

- Length validators and the column limit steer the length.
- Every value is checked against every `with:` and `without:` regex, the length rules and uniqueness.
- It is bounded. Unbounded quantifiers repeat at most 8 times past their minimum unless a length hint asks for more. Values are capped at 256 characters or the requested minimum.
- `srand` makes values repeatable.
- A regex that no string matches, or one that `regexp_parser` cannot parse, produces no candidate. If nothing works the bake raises (see [format exhaustion](../../skills/factory-bakery-diagnostics/references/diagnostics.md#format-exhaustion)). Supply the value yourself.

### Uniqueness

A column with a `uniqueness` validator, or a single-column unique index, is checked against the database and regenerated on collision. The bake also remembers every unique value it accepted during the current top-level bake, so two unsaved records in one graph do not collide at the root `save!`. After two collisions a candidate gets an entropy suffix, unless the column has a `format`, `inclusion`, `enum`, numericality rule, exact length, or no room under a length cap.

Not covered: a unique **composite** index, a unique rule enforced in a callback, and a literal value you pass for several children. See [FAQ](faq.md).

## What is never filled

| Attribute | Why | How to set it |
| --- | --- | --- |
| Primary key | Owned by the database | |
| `belongs_to` foreign keys (every part of a composite) | A made-up id dangles | `association`, a block, or an override |
| Polymorphic `*_type` / `*_id` | A made-up class name dangles | Same |
| STI `type` column | Owned by Rails | Bake the subclass |
| Counter caches | Maintained by Rails. A NOT NULL counter with no default gets `0` | |
| `created_at` / `updated_at` (`_on` too) | ActiveRecord stamps them on save. An unsaved `bake` leaves them `nil`, like `FactoryBot.build`; a validated one, or a model with `record_timestamps = false`, is still filled | An override or a `define` block |
| Writers named `*_remote_url`, `remote_url`, `remote_*url` | They usually download. A NOT NULL column with no default gets `''` | Declare it, override it, or use `skip` |
| Optional columns (default mode) | Nothing needs them | `fill_optional` |
| `has_many_attached` | No single file to pick | Declare it |

## `fill_optional`

```ruby
FactoryBakery.configure { |config| config.fill_optional = true }   # or FactoryBakery.fill_optional = true
FactoryBakery.bake(User)                                           # every column filled

FactoryBakery.bake(User, fill_optional: true)                      # one call
FactoryBakery.bake(User, fill_optional: false)                     # opt out of the global setting
FactoryBakery.bake(User, fill_optional: [:bio, :website])          # just these names
```

- The setting is validated. `fill_optional: 'true'` raises `ArgumentError: fill_optional must be true, false, or an array of attribute names, got "true"`.
- It applies to nested bakes made from declaration blocks too.
- Declarations, traits and overrides still win in every mode.
- A column filled only because you opted in is verified. If a custom validator or `validate` block rejects that value, the fill is put back to the column default (or `nil`) when that makes the record valid. A required column keeps its value.
- Side-effecting writers (`*_remote_url`) are not filled even with `fill_optional: true`.

## The verified fallback

[ADR-0006](../adr/0006-required-only-baking-and-verified-fallback.md). The lean record can be invalid for a reason no validator describes, for example a custom validator that needs an optional column. FactoryBakery handles this in two steps:

1. Build the lean record. Probe it with `valid?` **only if** a defaulted column has validators, or the model has validation the gem cannot read (a custom validator, `validates_with`, or a `validate` method). Rails' own autosave validators do not count, so a plain model gets no extra `valid?`.
2. If the probe says invalid, discard the attempt (its rows roll back in a savepoint when `FactoryBakery.savepoints` is on) and rebuild once with optional columns filled. The required-only result is always preferred.

What the fallback adds to errors:

- The names in the lean record's "can't be blank" / "must exist" errors steer the rebuild. An optional `belongs_to` named by such an error is built like a required one. If the error is on the foreign key column, the parent is inserted before validation.
- Only "missing" errors steer it. An "invalid" or "taken" error does not.
- The rebuild's opt-in applies to **that record only**. Nested parents stay lean.

Consequences you should plan for:

- **Declaration blocks can run twice** when the fallback fires. A block with a side effect outside the database (an HTTP call, a counter, a global setting) can repeat. Database writes in the first attempt are rolled back only with `FactoryBakery.savepoints = true`; by default they stay, so a block that saves a parent saves it twice.
- A fallback that cannot fix the record returns the record as it is. `bake` does not raise.
- With `fill_optional: true` globally there is no fallback and no savepoint.

## Conditional validators

Complementary guards (`presence` with `if: :remote?`, `absence` with `unless: :remote?`) used to merge into an unsatisfiable rule. They are now read per record: set `remote` with an override or declaration and the right rule applies. Evaluation uses the record after assignment, and the attribute being generated is briefly marked changed so `will_save_change_to_x?` conditions work.

## What inference cannot know

Write a definition for these ([ADR-0004](../adr/0004-extend-generation-within-discoverable-constraints.md)):

- Values from an app registry (report sources, providers, emoji, site settings).
- Cross-record rules (a follow must exist, an account must differ from another).
- Time rules that depend on "now" in a custom validator. (`comparison` and `numericality` bounds are handled.)
- Structured JSON payloads whose shape only your code knows.
- Concrete subclass choice for an abstract STI base.
- Rules that live in the database only (check constraints, composite unique indexes, triggers).

## Reproducible values

Strings, numbers and regex values use Ruby's global RNG. Call `srand(1234)` to repeat a run.
