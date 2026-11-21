# Sequel and ActiveModel

FactoryBakery's core does not name any framework. A **mapper** reads a framework's metadata and hands the core plain facts. Two mappers ship: ActiveRecord (loaded automatically when ActiveRecord is present) and Sequel (opt-in).

## ActiveModel objects

Any object with setters can be a target. Include `ActiveModel::Validations` and validator-driven inference works for it, with no schema:

```ruby
class Signup
  include ActiveModel::Model
  include ActiveModel::Validations
  attr_accessor :email, :age, :plan, :note

  validates :email, presence: true, format: { with: /\A[^@\s]+@example\.com\z/ }
  validates :age,   numericality: { only_integer: true, greater_than: 17 }
  validates :plan,  inclusion: { in: %w[free pro] }
end

s = FactoryBakery.bake(Signup)
s.email # => "c8hp1@example.com"
s.age   # => 48
s.plan  # => "pro"
s.note  # => nil: no validator, so nothing fills it
s.valid? # => true
```

(Output from a run against the current code. Values vary.)

Rules for these targets:

- The attribute universe is the validator-declared names. Attributes with no validator are left `nil`.
- A validated attribute is filled when an applicable validator rejects `nil` (the required-only rule). See [Heuristics](heuristics.md).
- `bake!` returns the object. It calls `save!` only if the object responds to it. There is no transaction.
- Declarations, traits, overrides and `initialize_with` work as for any target.

## Plain Ruby objects

No validators at all? Declared attributes and overrides are assigned through setters. Attributes with no value stay `nil`.

```ruby
class Contact
  attr_accessor :name, :email, :note
end

FactoryBakery.define(Contact) { name { 'Ada' } }

c = FactoryBakery.bake(Contact, email: 'ada@example.com')
c.note # => nil
FactoryBakery.bake!(Contact) # a Contact, nothing persisted
```

A class that no mapper claims keeps these duck-typed answers: no constraints, no guards, a null persistence adapter, the ordinary constructor.

`initialize_with` works for constructors with keyword arguments (verified with `Invoice(number:)`). See [Definitions](definitions.md#initialize_with).

## Sequel

```ruby
require 'factory_bakery/sequel'
```

The require registers a Sequel mapper that claims `Sequel::Model` descendants only. The ActiveRecord mapper keeps handling its models in the same process. `sequel` is an optional dependency; if it is missing the require raises:

```
factory_bakery/sequel requires the sequel gem, but it is not available.

Sequel support is opt-in and stays an optional dependency: the factory_bakery gemspec does not require sequel. Add the gem to your application's Gemfile:

  gem 'sequel'

Then run `bundle install` and require 'factory_bakery/sequel' again.
```

Example (run against in-memory SQLite):

```ruby
class Author < Sequel::Model
  plugin :validation_class_methods
  validates_presence_of :email
  validates_format_of :email, with: /\A[^@\s]+@example\.com\z/
end

FactoryBakery.bake(Author).email   # => "bD@example.com"
FactoryBakery.bake!(Author).pk     # => 1
```

| Sequel | Result |
| --- | --- |
| `db_schema` column types, `max_length`, nullability, defaults, `numeric(p, s)` | Same generators as the default mapper |
| Stored validations under `plugin :validation_class_methods` (presence, length, numericality, format, inclusion, acceptance) | The matching constraint |
| `validates_uniqueness_of`, single-column unique indexes | Uniqueness flag with a dataset-backed collision check |
| `many_to_one` reflections | Foreign keys are guard columns: left `nil`, never auto-built |
| `bake!` | Sequel `save` inside `db.transaction(savepoint: true)`, with the same rollback and verify contract |

### Limits (documented, not faked)

- **`plugin :validation_helpers` is not introspectable.** Those checks run inside `Model#validate`, which is code. Inference falls back to schema facts, and the verified fallback probes the model (a `validate` override counts as unreadable validation). Use `validation_class_methods` to get validator-driven generation.
- **Sequel associations are never auto-built.** `association :author` raises `no associations on Book; it is not ActiveRecord`. Assign the object in a block:
  ```ruby
  FactoryBakery.define(Book) { author { FactoryBakery.bake!(Author) } }
  ```
  A `Book` baked without that block has `author_id` `nil` (verified).
- Persisting JSON columns depends on Sequel's `serialization` plugin, a model concern outside the mapper.
- Conditional validators are not evaluated (the Sequel mapper returns unconditional constraints).

## Writing a mapper

The contract is in the comment at the top of `lib/factory_bakery/mapper_registry.rb`: `supports?` (the comment there says `supported?`, but `MapperRegistry.find_mapper` calls `supports?`, and the shipped mapper defines `supports?`), `attribute_universe`, `constraints_for`, `guard_columns`, `alias_groups`, `belongs_to_association_names`, `association_introspection`, `uniqueness_*`, `validator_descriptions`, `persistence_adapter`, `construct`. Register it with `FactoryBakery::MapperRegistry.register(mapper)`. The first registered mapper that supports a class wins. A mapper that does not implement `custom_validation?` is treated as "verify", the conservative default. The architecture guard spec fails the suite if core code names a framework constant.
