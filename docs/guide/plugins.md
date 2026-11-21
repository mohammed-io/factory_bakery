# Plugins

Core is framework-agnostic ([ADR-0001](../adr/0001-framework-agnostic-core-mapper-plugins.md)). Two kinds of extension sit on top of it.

| Kind | Purpose | Registered with |
| --- | --- | --- |
| **Mapper** | Reads one ORM or validation framework (ActiveRecord, Sequel). Turns it into neutral facts | `FactoryBakery::MapperRegistry.register(mapper)` |
| **Plugin** | Adds DSL, contributes values, or acts after an object is built (associations, attachments) | `FactoryBakery.register_plugin(plugin)` |

This page is about plugins. Mappers are covered under [Sequel and ActiveModel](sequel-and-activemodel.md).

## Shipped plugins

| Require | What it adds | DSL |
| --- | --- | --- |
| `factory_bakery/associations` | Auto-building and the `association` DSL | `association` |
| `factory_bakery/attachments` | Fills required file attachments | none |

`require 'factory_bakery'` alone registers no plugins (`PluginRegistry.plugins` is empty).

## The three hooks

A plugin is any object. It may implement any subset of these methods. Core calls only the ones it responds to.

| Hook | Called | Returns |
| --- | --- | --- |
| `dsl_module` | Once, at registration | A `Module` whose public instance methods become DSL methods in `define` and `trait` blocks |
| `heuristic_values(klass, context, taken)` | While values are resolved, before heuristics | A Hash of attribute name to value. Names in `taken` are ignored |
| `after_instantiate(object, declarations, context)` | After plain values are assigned | Anything. Use it to mutate `object` |

- `taken` is the list of attribute names (strings) already decided by a declaration, trait, override or `initialize_with`. Alias groups are expanded.
- `declarations` is **this plugin's own bucket**: the entries its DSL methods recorded, in order (base, then traits).
- `context` is the `FactoryBakery::BuildContext` of the current bake (its `path`, `depth`, and so on).

## How core routes a DSL call

1. When a definition builds, core extends the definition with a scope module made from every registered plugin's `dsl_module`.
2. Each DSL method is wrapped so core knows **which plugin** is running.
3. Inside your method, call `record_plugin_declaration(entry)`. Core stores `entry` in your plugin's bucket.
4. After the object exists, core calls your `after_instantiate` with that bucket.

Because traits are evaluated the same way, a plugin DSL method works inside `trait` blocks, and a later trait's declaration is appended after the base's.

The entry can be anything. If it responds to `name`, that name counts as **taken** for [precedence](overrides-and-precedence.md), so inference and other plugins leave it alone. Otherwise `entry.to_s` is used.

## Ordering

- Plugins run in **registration order**, for both `heuristic_values` and `after_instantiate`.
- If two plugins return the same key from `heuristic_values`, the **later** one wins.
- Within one alias group, the association name wins over its foreign key and type columns regardless of hash order.
- Registering the same plugin object twice is a no-op.
- Two plugins may not define the same DSL method name. The second `register_plugin` raises `DSL method :downcase is already provided by another plugin`.

Requiring the associations plugin and your own plugin in different orders can therefore change a result when both set the same key. Register yours last if it should win.

## Reserved name

`association` is reserved. Using it without a plugin that provides it raises `` `association` requires the associations plugin: require 'factory_bakery/associations' ``. Any **other** unknown name in a definition is read as an attribute declaration with no block. It is silently ignored, so a plugin DSL method used after the plugin is unregistered does nothing and does not raise.

## Worked example

A plugin that (1) gives every model with a `locale` column the value `'en'` unless something decided it, and (2) adds a `downcase :email` DSL that normalizes an attribute after it is set. Run against SQLite in the author's check.

```ruby
# spec/support/downcasing_plugin.rb
module Downcasing
  module DSL
    def downcase(*names)
      names.each { |name| record_plugin_declaration(name) }
    end
  end

  class << self
    def dsl_module = DSL

    def heuristic_values(klass, _context, taken)
      return {} unless klass.respond_to?(:column_names) && klass.column_names.include?('locale')
      return {} if taken.include?('locale')

      { 'locale' => 'en' }
    end

    def after_instantiate(object, declarations, _context)
      declarations.each do |name|
        object.public_send("#{name}=", object.public_send(name).to_s.downcase)
      end
    end
  end
end

FactoryBakery.register_plugin(Downcasing)
```

```ruby
FactoryBakery.define(User) do
  email { 'ADA@Example.COM' }
  downcase :email
  trait(:german) { locale { 'de' } }
end

FactoryBakery.bake(User).then { [_1.email, _1.locale] } # => ["ada@example.com", "en"]
FactoryBakery.bake(User, :german).locale                # => "de"   (trait beats the plugin)
FactoryBakery.bake(User, locale: 'fr').locale           # => "fr"   (override beats the plugin)
FactoryBakery.bake(User, email: 'X@Y.Z').email          # => "x@y.z" (after_instantiate runs last)
```

Notes from the example:

- `after_instantiate` runs after values are assigned, so it sees the final `email`, including a call-site override.
- `heuristic_values` is below declarations, traits and overrides in precedence, so those beat the plugin value.
- `record_plugin_declaration` is only valid while a DSL method of yours is running. Outside one it raises `No plugin DSL call is in progress`.
- DSL methods must be **public instance methods defined directly on the module** (`instance_methods(false)`). Methods that come from a module included into your DSL module are not wrapped, so `record_plugin_declaration` would raise inside them (read from the code, not run).

## Registry API

| Call | Effect |
| --- | --- |
| `FactoryBakery.register_plugin(plugin)` | Adds a plugin. Idempotent per object |
| `FactoryBakery.unregister_plugin(plugin)` | Removes it and rebuilds the DSL scope |
| `FactoryBakery.reset_plugins!` | Removes **every** plugin, including associations and attachments. For test isolation |
| `FactoryBakery::PluginRegistry.plugins` | The frozen list, in order |

`reset_plugins!` also removes the associations plugin. If your suite calls it between examples, require or register the plugins again (the Railtie's `RailConfig.configure` does this idempotently on boot).

## Writing a good plugin

- Keep framework reads out of it. Ask the mapper through `FactoryBakery::MapperRegistry` (`association_introspection`, `constraints_for`, `persistence_adapter`).
- Do not write to the database from `heuristic_values`. It can run in a fallback attempt that is rolled back.
- Do not rely on a hook running once: the [verified fallback](heuristics.md#the-verified-fallback) can build a record twice.
- Treat `BuildContext` as internal. Use `context.path` and `context.depth` if you must.
