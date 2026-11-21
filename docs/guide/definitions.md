# Definitions

A definition is optional. Without one, `bake(User)` works from inference alone. Add a definition when a test needs a specific value, or when the model cannot bake without app knowledge (a registry, a custom validator).

## `FactoryBakery.define`

```ruby
FactoryBakery.define(User) do
  name  { 'Ada Lovelace' }
  email { "user#{SecureRandom.hex(4)}@example.com" }

  trait :admin do
    role { 'admin' }
  end
end
```

```ruby
FactoryBakery.define(target, klass: nil, &block)
```

- `target` is a class or a symbol. See [named factories](#named-factories).
- Registering the same target again replaces the previous definition silently (last one wins). This makes reloading safe.
- A class definition applies when you bake that class: `bake(User)`.

## Attribute blocks

An attribute is declared with a name and a block:

```ruby
name { 'Ada Lovelace' }
```

Each winning block runs once per build attempt. A verified fallback rebuild evaluates the blocks again for its new record.

Static declarations such as `name 'Ada'` raise `FactoryBakery::Error` when the factory is evaluated. Use `name { 'Ada' }` to assign a value or `skip :name` to omit the attribute.

### What a block can see

An attribute block can read a sibling by name, including one declared later:

```ruby
FactoryBakery.define(User) do
  label { "#{name}-x" }
  name  { 'Ada' }
end

FactoryBakery.bake(User, name: 'Grace').label # => "Grace-x"
```

Call-site overrides (including `nil` and `false`) win, followed by the last applicable trait or factory declaration, then inference. A read can use a plugin's heuristic value. Explicit `association` declarations and other plugin hooks that populate the finished object run after the attribute blocks. To use such an association as an input, supply it as an override or declare it directly with an attribute block.

Reads respect `skip` and `fill_optional`. An optional attribute left unfilled reads as its current default or `nil`. The verifier keeps generated optional values consumed by a declaration so the record and derived attributes stay consistent. Cycles raise `FactoryBakery::Error` with the chain, for example `label -> name -> label`.

Blocks can still use constants, lexical locals, and calls such as `FactoryBakery.bake!`. They run in an attribute scope, which resolves sibling reads on demand. Blocks with no dependencies run in declaration order.

A local declared **outside** `define` (at the top of the file) is shared across bakes. That is how you build a counter:

```ruby
counter = 0
FactoryBakery.define(User) do
  email { "user#{counter += 1}@example.com" }
end
```

The counter resets when the file is loaded again. There is no `sequence` DSL.

### Declaring a name that collides with the DSL

`skip`, `trait`, `initialize_with`, `add_attribute` and `association` (with the plugin) are DSL methods. For an attribute with one of those names, use the explicit form:

```ruby
FactoryBakery.define(Account) do
  add_attribute(:skip) { 'a value' }
end
```

Use `add_attribute(:class) { 'premium' }` for names Ruby already owns. For reserved syntax such as `alias`, use the explicit declaration form as well.

## Blocks passed to `bake` and `bake!`

Both methods yield the resulting record once and return that same record. `bake` yields after the build and any verified fallback. `bake!` yields after saving, verifying persistence, and leaving its transaction or savepoint. A block exception propagates to the caller. The bake's own transaction has already finished, and any enclosing transaction still applies.

### Declaring an attribute the model does not have

Nothing happens. Values are assigned through setters, and a setter that does not exist is skipped without error. A typo in an attribute name is therefore silent.

## `skip`: leave an attribute alone

`skip` leaves attributes unassigned. The model keeps the value it has (usually a database default or `nil`) and the setter is never called.

```ruby
FactoryBakery.define(Account) do
  skip :avatar_remote_url, :header_remote_url
end
```

Use it for setters with side effects, and to stop the association plugin from building an edge. `skip :account` suppresses the association, its foreign key and its polymorphic type column together.

`skip` takes names only. With a block (or no names) it raises:

```
skip is the attribute-omission DSL method; use add_attribute(:skip) { ... } to declare a real attribute named skip
```

`skip` has the same precedence as a declaration. A trait can replace it. A call-site value always wins, including `nil`, which calls the setter. See [Overrides and precedence](overrides-and-precedence.md).

## `initialize_with`

For constructors that need arguments:

```ruby
class Invoice
  attr_reader :number
  def initialize(number:) = @number = number
end

FactoryBakery.define(Invoice) do
  initialize_with(number: 'INV-001')
end
```

It takes one Hash. How the hash is used depends on the constructor:

| Constructor | What happens |
| --- | --- |
| No arguments | `new`, then each key goes through its setter |
| Keyword arguments only | `new(**hash)` |
| Anything else (including ActiveRecord) | `new(hash)` |

`initialize_with` values count as decided. Inference does not overwrite them.

### Models whose `new` raises

Baking retries only after a failure, in this order: `new`; `unscoped { new }` (a raising `default_scope`); callback-free construction (a raising `after_initialize`). If all fail, the original error is re-raised with this note appended: `(FactoryBakery also tried unscoped and callback-free construction)`. Callback-free construction skips app initialization, so it is the last resort.

## Named factories

A symbol names a factory. Bind it to a class with `klass:`:

```ruby
FactoryBakery.define(:customer, klass: User) do
  name { 'Ada' }
end

FactoryBakery.bake(:customer) # => a User
```

Without `klass:`, the class is found at bake time by camelizing the symbol (`:admin_user` becomes `AdminUser`). This lets definition files load before models exist.

```
Could not resolve a class for factory :ghost (tried "Ghost"); pass klass: when defining it
```

Other errors:

```
No factory is registered for :nothing
Unsupported bake target "User"; pass a class or a registered symbol
```

A symbol is resolved on every bake and never cached, so symbol factories survive Rails code reloading. A class key points at the class object that existed when the file loaded. After a reload, that object is stale. (Read from the code, not run.)

Class and symbol registrations are separate keys. `define(User)` and `define(:user, klass: User)` do not share a block.

## Loading definition files

### In Rails

Definition files load once, after the app initializes, from one directory: `spec/bakery` or `test/bakery` when factory_bot is detected, else the first existing of `spec/factories`, `test/factories`, `factories`. All `*.rb` files below it load recursively, in sorted order. Configure it with `config.factory_bakery.definition_paths`. See [Rails](rails.md#configuration).

### Outside Rails

```ruby
FactoryBakery.definition_paths = ['spec/bakery']
FactoryBakery.find_definitions
```

- A single string is accepted as well as an array.
- Paths that do not exist are skipped.
- Files are evaluated with `Kernel.load`, so calling `find_definitions` again re-evaluates them. A file error propagates, and files from earlier paths are already loaded.
- `definition_paths` is empty until something sets it.

### One definition per file, or many?

The loader does not care. Convention: one file per model, named after it (`spec/bakery/post.rb`). That is also where `bin/rails g factory_bakery:definition Post` writes it: the first `definition_paths` entry, or the default directory (see [Rails](rails.md#configuration)). A namespaced model goes in a matching subdirectory (`Admin::Post` is `admin/post.rb`).

## When to write a definition

| Situation | Write |
| --- | --- |
| A test asserts on an exact value | One attribute block |
| A validator reads app state (a registry, a site setting) | A block that returns a value from that state |
| A format no regex can describe | A block with a literal or generator |
| A setter has side effects (network, jobs) | `skip :attr` |
| A parent must be saved before validation | [`association :x, persist: true`](associations.md#persist) |
| A model needs a graph built a special way | An association block, or a block that calls `bake!` |

If none of these apply, delete the definition. See [Heuristics](heuristics.md).
