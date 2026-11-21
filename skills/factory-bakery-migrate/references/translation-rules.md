# Translation rules: factory_bot to FactoryBakery

Translate one factory at a time into the **new** directory (`spec/bakery` or `test/bakery`). Never edit the old factory file. Translate 1:1 first. Simplification is a separate, user-approved step.

## File and header

```ruby
# before: spec/factories/posts.rb
FactoryBot.define do
  factory :post do
    # ...
  end
end
```

```ruby
# after: spec/bakery/post.rb
FactoryBakery.define(Post) do
  # ...
end
```

| factory_bot | FactoryBakery |
| --- | --- |
| `factory :post` (class `Post`) | `FactoryBakery.define(Post)` |
| `factory :admin, class: 'User'` | `FactoryBakery.define(:admin, klass: User)` |
| `factory :admin, class: User` | `FactoryBakery.define(:admin, klass: User)` |
| `factory :post` where call sites only use `create(:post)` | `define(Post)` and the call becomes `bake!(Post)` |
| One file, many factories | One definition per model, in one file per model |

Use a **class** key when the factory name equals the class (`:post` and `Post`). Use a **symbol with `klass:`** when it does not, or when tests create the same class under several names.

## Attributes

| factory_bot | FactoryBakery | Note |
| --- | --- | --- |
| `title { 'x' }` | `title { 'x' }` | Same |
| `title 'x'` | `title { 'x' }` | The static form does nothing in FactoryBakery |
| `title { Faker::Lorem.sentence }` | `title { Faker::Lorem.sentence }` (1:1) | Droppable later: inference covers it |
| `created_at { 1.day.ago }` | `created_at { 1.day.ago }` | Keep if a test depends on it |
| `title { nil }` | `title { nil }` | Explicit `nil` is honored |
| `email { "#{name}@x.com" }` | See caveat: sibling reads | Blocker if a test overrides `name` |
| `skip_create` | Delete | `bake` never saves |

## Sequences

```ruby
# before
sequence(:email) { |n| "user#{n}@example.com" }
```

```ruby
# after: a counter at the top of the file
counter = 0
FactoryBakery.define(User) do
  email { "user#{counter += 1}@example.com" }
end
```

If the column is `uniqueness`-validated and no test checks the shape, the 1:1 translation is `email { "user#{SecureRandom.hex(4)}@example.com" }`. The simplified form is no line at all.

## Associations

| factory_bot | FactoryBakery |
| --- | --- |
| `association :author` | `association :author` (add the class when the name differs: `association :author, User`) |
| `association :author, factory: :user` | `association :author, User` |
| `association :author, factory: :admin` where `:admin` is registered | `association :author, factory: :admin` |
| `association :author, :admin` | `association :author, :admin` |
| `association :author, name: 'Ann'` | `association :author, with: { name: 'Ann' }` |
| `association :author, strategy: :create` | `association :author, persist: true` |
| `association :author, strategy: :build` | `association :author` |
| bare `author` (implicit association) | `association :author`, or nothing when the edge is required |
| `author { association :user }` | `association :author, User` |
| `author { create(:user) }` | `author { FactoryBakery.bake!(User) }` |
| `author { build(:user) }` | `author { FactoryBakery.bake(User) }` |
| `comments { build_list(:comment, 3) }` | `association :comments, count: 3` |
| `after(:build) { \|p\| p.comments << build(:comment) }` | Not supported (callback) |
| polymorphic `commentable { association :post }` | `association :commentable, Post` |
| `post { nil }` | `post { nil }` |

### Child blocks must pass the owner

```ruby
# before
comments { build_list(:comment, 2) }
```

```ruby
# after (a block, when the children need custom values)
association(:comments) { |post| Array.new(2) { |i| FactoryBakery.bake(Comment, post: post, body: "c#{i}") } }
```

`association :comments, count: 2` is the simple form.

## Traits

| factory_bot | FactoryBakery |
| --- | --- |
| `trait :admin do ... end` | `trait :admin do ... end` (same) |
| trait using another trait (`admin` inside a trait body) | Repeat the lines. A trait cannot call a trait |
| `factory :admin, parent: :user` | A trait on the parent: `trait :admin do role { 'admin' } end`. The call becomes `bake!(User, :admin)` |
| `factory :admin, parent: :user do ... end` with `class: 'Admin'` | A second definition: `define(:admin, klass: Admin)` with the parent's lines repeated |
| `traits_for_enum :status` | A trait per state a test uses, or none (enum inference) |
| `trait :x` with `transient` | See transients |

## Transients and callbacks

| factory_bot | FactoryBakery |
| --- | --- |
| `transient do foo { 1 } end` used only to compute attributes | A local inside `define`: `foo = 1` |
| `transient` passed at the call site | Not supported. Blocker |
| `after(:build)`, `after(:create)`, `before(:create)`, `callback` | Not supported. Pre-save record work can be an `association` block. Otherwise a blocker |
| `initialize_with { new(a: 1) }` | `initialize_with(a: 1)` |
| `initialize_with { new(a: name) }` | Blocker (a block, and it reads a sibling) |

## Call sites (renames only)

Only the factory call changes. Arguments after the name carry over unchanged.

| Before | After |
| --- | --- |
| `create(:post)` | `FactoryBakery.bake!(Post)` |
| `create(:post, title: 'x')` | `FactoryBakery.bake!(Post, title: 'x')` |
| `create(:post, :published, title: 'x')` | `FactoryBakery.bake!(Post, :published, title: 'x')` |
| `build(:post)` | `FactoryBakery.bake(Post)` |
| `create(:admin)` (symbol factory) | `FactoryBakery.bake!(:admin)` |
| `FactoryBot.create(:post)` | `FactoryBakery.bake!(Post)` |
| `create_list(:post, 3)` | `Array.new(3) { FactoryBakery.bake!(Post) }` |
| `create_list(:post, 3, :published, title: 'x')` | `Array.new(3) { FactoryBakery.bake!(Post, :published, title: 'x') }` |
| `build_list(:post, 2)` | `Array.new(2) { FactoryBakery.bake(Post) }` |
| `create_pair(:post)` | `Array.new(2) { FactoryBakery.bake!(Post) }` |
| `attributes_for(:post)` | `attributes_for(Post)` through a helper (see below) |
| `build_stubbed(:post)` | Blocker |
| `create(:post) { \|p\| ... }` | Blocker (the block is ignored) |

Which spelling for the name? A symbol name maps to the class (`:post` to `Post`). If the factory was registered under a different name than the class, keep the symbol (`bake!(:admin)`) and register it with `klass:`.

### The helper for `attributes_for`

Only when tests use it. A new file, so the test diff stays renames:

```ruby
# spec/support/bakery_helpers.rb
module BakeryHelpers
  def attributes_for(klass, *traits, **overrides)
    FactoryBakery.bake(klass, *traits, **overrides)
      .attributes.except('id', 'created_at', 'updated_at').compact
  end
end

RSpec.configure { |config| config.include BakeryHelpers }
```

String keys, no associations. If a test needs symbol keys, add `.symbolize_keys` **inside the helper**. Do not touch the test.

## Putting a definition to bed

After translating, the 1:1 definition for a model is correct but verbose. The next step is to run `doctor` and **ask the user** whether to simplify. Keep a line only when:

1. A test depends on that exact value, or
2. The model cannot bake without it. Say which: custom validator, registry, format, side effect, cross-record rule, cycle, view.

## Worked example

Before:

```ruby
FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    name { Faker::Name.name }
    password { 'secret123' }
    role { 'member' }
    association :account

    trait :admin do
      role { 'admin' }
    end
  end
end
```

1:1 translation:

```ruby
counter = 0
FactoryBakery.define(User) do
  email { "user#{counter += 1}@example.com" }
  name { Faker::Name.name }
  password { 'secret123' }
  role { 'member' }
  association :account

  trait :admin do
    role { 'admin' }
  end
end
```

After the user agrees to reduce, assuming `email` has `uniqueness` (no test checks its shape), `name` is NOT NULL, `password` uses `has_secure_password`, `role` is an `inclusion` with default `'member'`, `account` is a required `belongs_to`, and a test asserts `user.admin?` through `:admin`:

```ruby
FactoryBakery.define(User) do
  trait :admin do
    role { 'admin' }   # a test asserts on this state
  end
end
```
