# Migrating from factory_bot

FactoryBakery is not a factory_bot clone. factory_bot describes every attribute. FactoryBakery infers them and you describe the exceptions. A migration is therefore mostly **deleting** code, plus renaming call sites.

An agent skill performs this migration step by step: [`skills/factory-bakery-migrate`](../../skills/factory-bakery-migrate/SKILL.md). This page is the human version.

## Ground rules

These rules decide how the migration is done. The skill enforces them.

1. **Work in isolation.** Start in a separate git worktree on a separate branch. Never touch your main checkout or uncommitted changes.
2. **The suite must pass exactly as before.** Same examples, same count, no new pending or skipped examples.
3. **Test files change only by renaming factory calls.** `create(:post)` becomes `FactoryBakery.bake!(Post)`. No assertion, setup, expectation or structure changes. Anything that needs more than a rename is solved in definitions or a helper, or reported as a blocker.
4. **Simplify by default, but ask.** After translating, the migration proposes dropping every factory whose values inference already produces. You choose between "reduce definitions and rely on automatic inference (recommended)" and "keep a 1:1 translation".
5. **Two-way doors first, one-way doors last.** Cheap-to-undo steps proceed. Hard-to-undo steps need your explicit confirmation and happen last, after the full suite is green.
6. **Nothing is deleted automatically.** The old factories and the gem are removed only if you answer "delete" at the very end, in a separate commit you can revert.

### Doors

| Two-way doors (cheap to undo). Proceed | One-way doors (hard to undo). Ask first, do last |
| --- | --- |
| Adding the `factory_bakery` gem | Deleting factory_bot factories |
| Side-by-side config (`definition_paths`) | Removing the `factory_bot` / `factory_bot_rails` gem |
| Adding FactoryBakery definitions | Deleting fixtures, fabricators, blueprints |
| Renaming call sites (one commit per batch) | Changing DB constraints or app validations so baking is easier |
| Adding a thin helper in `spec/support` | Removing test data the suite relies on |
| Running `factory_bakery:doctor` | Squashing or rewriting history |

The full table, with the reason for each row, is in the [skill's door reference](../../skills/factory-bakery-migrate/references/doors.md).

## Concept mapping

| factory_bot | FactoryBakery |
| --- | --- |
| `FactoryBot.define { factory :user { ... } }` | `FactoryBakery.define(User) { ... }` |
| `factory :admin, class: 'User'` | `FactoryBakery.define(:admin, klass: User) { ... }` |
| `factory :admin, parent: :user` / nested `factory` | A trait on the parent, or a second definition. A subclass with no definition of its own (`Admin < User`) already uses `User`'s |
| `aliases: [:author]` | A second `define(:author, klass: User, &same_block)` |
| `name { 'Ada' }` | `name { 'Ada' }` (same) |
| `name 'Ada'` (static) | `name { 'Ada' }`. The static form raises with the block syntax |
| Attribute that inference already produces | Delete the line |
| `trait :admin do ... end` | `trait :admin do ... end` (same, local to the definition) |
| `traits_for_enum :status` | Delete (enum inference), or one trait per state a test needs |
| `sequence(:email) { \|n\| ... }` | A counter local at the top of the file, or `SecureRandom`. Or delete if the column is unique-validated |
| `transient do ... end` | A local variable: in the `define` body for a constant, inside the attribute block for a computed or random value (the `define` body runs once). See the limits below |
| `email { "#{name}@x.com" }` | Same block. The resolved `name` includes call-site overrides and applied traits |
| `association :author` | `association :author` (plugin loaded) |
| `association :author, factory: :editor` | `association :author, factory: :editor` |
| `association :author, :admin, name: 'Ann'` | `association :author, :admin, with: { name: 'Ann' }` |
| `association :author, strategy: :create` | `association :author, persist: true` |
| Implicit association (a bare `author` in the factory) | Delete. A required `belongs_to` is built automatically in `:required_only` |
| `initialize_with { new(a: 1) }` | `initialize_with(a: 1)` (a Hash only. A block does not map) |
| `after(:build)`, `after(:create)`, `before(:create)`, `callback` | Not supported. See the limits below |
| `to_create`, `skip_create` | Not needed. `bake` never saves |
| `build(:post)` | `FactoryBakery.bake(Post)` — pass `validate: false` for the closest to `build`: no probe, no uniqueness check, the record may be invalid |
| `create(:post)` | `FactoryBakery.bake!(Post)` |
| `build(:post) { \|post\| ... }` / `create(:post) { \|post\| ... }` | Keep the block on `bake` / `bake!`. `bake!` yields after its transaction or savepoint finishes |
| `build_stubbed(:post)` | No equivalent |
| `attributes_for(:post)` | No built-in. A [thin helper](testing-recipes.md#attribute-hash-for-a-request-spec) |
| `create_list(:post, 3)`, `build_list`, `create_pair` | `Array.new(3) { FactoryBakery.bake!(Post) }` (or `bake`) |
| `create(:post, :published, title: 'x')` | `FactoryBakery.bake!(Post, :published, title: 'x')` |
| `use_parent_strategy` | The default: `bake` builds the whole graph unsaved, `bake!` saves it in one transaction |
| `FactoryBot.lint` | `bin/rails factory_bakery:doctor`. It checks models, not named factories or traits |
| `include FactoryBot::Syntax::Methods` | `FactoryBakery::Methods` gives bare `bake` and `bake!`. The migration uses the fully qualified form so call sites stay explicit |
| `FactoryBot.find_definitions` / `definition_file_paths` | `FactoryBakery.find_definitions` / `definition_paths` |

## Step 0: Isolate

Work in a worktree on its own branch. Replace `<repo>` with your repository directory name.

```sh
git worktree add ../<repo>-bakery-migration -b factory-bakery-migration
cd ../<repo>-bakery-migration
```

Your main checkout and its uncommitted changes are never touched. To abandon the migration:

```sh
cd ..
git worktree remove ../<repo>-bakery-migration
git branch -D factory-bakery-migration
```

Capture a **baseline** in the worktree before any change: the full suite's example count, failures and pending. The migration is done only when the same numbers come back.

## Step 1: Inventory

List what exists. Count the factories, the call-site forms, and anything unusual.

| Look for | Why it matters |
| --- | --- |
| `factory :` / `FactoryBot.define` files | What to translate |
| `sequence`, `transient`, `after(`, `before(`, `callback(` | Not supported or needs care |
| Attributes that read other attributes | Supported: `email { "#{name}@example.com" }` |
| `build_stubbed`, `attributes_for`, `create_list` | Special call-site handling |
| `create(:x) { \|x\| ... }` blocks | Keep the block on `bake!` |
| `initialize_with { ... }` blocks | Hash only |
| Nested factories and `parent:` | A subclass inherits its parent class's definition; otherwise a trait or a second definition |
| `FactoryBot.lint` | Replaced by doctor |
| Custom validators, registries, callbacks on models | Likely definitions that must stay |

## Step 2: Set up side by side

Install the gem next to factory_bot (a two-way door):

```ruby
# Gemfile
group :development, :test do
  gem 'factory_bakery', git: 'https://github.com/mohammed-io/factory_bakery.git'
end
```

**Edge case: both gems load `spec/factories`.** factory_bot's documented default definition paths include `spec/factories` and `test/factories`, which are the directories FactoryBakery loads when factory_bot is absent. Each gem would evaluate the other's files, and factory_bot files loaded twice can raise a duplicate-definition error. (Stated from the two gems' documented defaults. The author did not run a collision.) FactoryBakery avoids this when it detects factory_bot (the `FactoryBot` constant is defined, or a file under `spec/factories`, `test/factories` or `factories` starts a line with `FactoryBot.define`): its default directory becomes `spec/bakery` or `test/bakery`. Do not rely on detection. Give FactoryBakery its own directory explicitly. The install generator does both steps:

```sh
bin/rails g factory_bakery:install
```

It creates `spec/bakery` (`test/bakery` for Minitest) and an initializer with `config.definition_paths = ["spec/bakery"]`. By hand:

```ruby
# config/application.rb
config.factory_bakery.definition_paths = [Rails.root.join('spec/bakery').to_s]
config.factory_bakery.associations     = { mode: :required_only }
```

Use `test/bakery` for Minitest. Create the directory. Then wire the test helper:

```ruby
RSpec.configure { |config| config.include FactoryBakery::Methods }  # optional
```

If the project uses Sorbet, copy the gem's `rbi/factory_bakery.rbi` into `sorbet/rbi/shims/`. Class targets give typed returns and block arguments for both bake forms. Bakes with a symbol target return `T.untyped`. Sorbet does not check trait names or attribute overrides. See [Types (Sorbet)](types.md).

Run the suite. It must still match the baseline. Nothing uses FactoryBakery yet.

## Step 3: Translate definitions

Translate **one factory at a time**. Keep each as a plain translation first. Simplification is step 4.

```ruby
# before: spec/factories/posts.rb
FactoryBot.define do
  factory :post do
    title { Faker::Lorem.sentence }
    body  { 'text' }
    association :author, factory: :user
    status { :draft }

    trait :published do
      status { :published }
      published_at { Time.current }
    end
  end
end
```

```ruby
# after: spec/bakery/post.rb  (plain translation)
FactoryBakery.define(Post) do
  title { Faker::Lorem.sentence }
  body  { 'text' }
  association :author, User
  status { :draft }

  trait :published do
    status { :published }
    published_at { Time.current }
  end
end
```

Per-construct rules:

| factory_bot | Translate to |
| --- | --- |
| Static attribute `x 1` | `x { 1 }` |
| `sequence(:email) { \|n\| "u#{n}@x.com" }` | `counter = 0` at the top of the file, then `email { "u#{counter += 1}@x.com" }` |
| `association :x` | `association :x` (add the class if the name differs: `association :author, User`) |
| `association :x, name: 'a'` | `association :x, with: { name: 'a' }` |
| `association :x, strategy: :create` | `association :x, persist: true` |
| `factory :child, parent: :base` | Put the child's difference in a trait, or write a second definition with the parent's lines repeated |
| `factory :x, class: 'Ns::Model'` | `define(:x, klass: Ns::Model)` |
| `aliases: [:author]` | Share the block: `blk = proc { ... }`, `define(User, &blk)`, `define(:author, klass: User, &blk)` |
| `initialize_with { new(a) }` | Cannot be mapped. See the limits |

## Step 4: Run doctor, then simplify (ask first)

Run doctor on the translated models (see [Rails](rails.md#rake-tasks)). Name the models, comma separated. With no names it checks every Active Record model in the app and exits `1` if any fails, including models your tests never bake.

```sh
bin/rails 'factory_bakery:doctor[Post]'
```

For each translated factory, compare its lines with what inference produces. Present the choice to the user:

- **Reduce definitions and rely on automatic inference (recommended).**
- **Keep a 1:1 translation of every factory.**

Reduce only if the user agrees. When reducing, **keep a line only if** one of these is true, and say which:

1. **A test depends on that exact value.** A test asserts on it, or looks the record up by it.
2. **The model cannot bake without it.** A custom validator, a registry, a format no regex describes, a side-effecting setter, or an app rule.

Everything else goes. See [What inference covers](#what-inference-covers).

```ruby
# after simplification: spec/bakery/post.rb
FactoryBakery.define(Post) do
  trait :published do
    status { :published }               # a test asserts on this state
    published_at { Time.current }
  end
end
```

`title`, `body`, `author`, and `status { :draft }` are gone: inference fills them (or the `draft` default is kept).

## Step 5: Rewrite call sites. Renames only

Test files may change only by renaming the factory call. Use these rewrites.

| factory_bot | FactoryBakery |
| --- | --- |
| `create(:post)` | `FactoryBakery.bake!(Post)` |
| `create(:post, title: 'x')` | `FactoryBakery.bake!(Post, title: 'x')` |
| `create(:post, :published)` | `FactoryBakery.bake!(Post, :published)` |
| `create(:user, :admin, name: 'x')` | `FactoryBakery.bake!(User, :admin, name: 'x')` |
| `build(:post)` | `FactoryBakery.bake(Post)` |
| `create(:user) { \|user\| user.reload }` | `FactoryBakery.bake!(User) { \|user\| user.reload }` |
| `create(:admin)` where `factory :admin, class: 'User'` | `FactoryBakery.bake!(:admin)` (needs `define(:admin, klass: User)`) |
| `create_list(:post, 3)` | `Array.new(3) { FactoryBakery.bake!(Post) }` |
| `build_list(:post, 3)` | `Array.new(3) { FactoryBakery.bake(Post) }` |
| `create_pair(:post)` | `Array.new(2) { FactoryBakery.bake!(Post) }` |
| `attributes_for(:post)` | `attributes_for(Post)` through a helper that keeps the call a rename |
| `build_stubbed(:post)` | Blocker. Report it |

For new code, `FactoryBakery.recipe(User, :admin).bake!(name: 'x')` is an optional spelling for the same `create` mapping. The `build` equivalent is `FactoryBakery.recipe(Post).bake`. Use the plain renames in the table by default during migration so test files change only by renaming factory calls.

Do it in small batches, one commit each. Run the suite after each batch.

Keep an existing block on a single-record `bake` or `bake!` call. Both yield the record, including when called on a recipe. If a call site relies on `build_stubbed` or needs behavior the definition cannot give, stop and report it. See [what cannot be migrated](#what-cannot-be-migrated-mechanically).

### Checking that only calls changed

Every changed test line must be a factory-call rename. Check it from the worktree:

```sh
git diff -U0 --no-color main...HEAD -- spec test
```

The removed lines must be old factory calls. The added lines must be their paired replacements. The skill ships a checker procedure: [`references/verification.md`](../../skills/factory-bakery-migrate/references/verification.md). Then run the full suite and compare it with the baseline from step 0: same example count, same failures (none), same pending count.

## Step 6: Verify and compare

- Full suite: same example count, 0 failures, no new pending or skipped.
- `git diff` of test files: renames only.
- `bin/rails 'factory_bakery:doctor[Post,Comment]'` (every model your tests bake) exits `0` and ends with `N valid, 0 needs definition`. The unqualified `bin/rails factory_bakery:doctor` covers all models and may fail on models you never baked.
- Optionally, run the suite twice with different seeds. FactoryBakery values are random, so a test that relied on a fixed fake value shows up.

## Step 7: Ask about the old factories. The last one-way door

When everything is done and the suite is green, **ask** the user. Never delete on your own. Present both options:

| Option | What it means |
| --- | --- |
| **Keep** | The old factory_bot files and gem stay. Nothing is lost. Both gems keep loading, the side-by-side directory stays, and the repository carries two factory systems. Safe, but the clutter remains. |
| **Delete** | The old factory files and the `factory_bot` gem are removed, in **one separate commit**, so it can be reverted with `git revert`. Make sure no test, rake task or seed still calls factory_bot. |

Delete only on an explicit "delete" answer. Then:

1. Delete the old factory files and the factory_bot gem entry in a single commit that touches nothing else.
2. Run the full suite again. It must still match the baseline.
3. Consider moving `spec/bakery` to `spec/factories` and unsetting `definition_paths`. That is another commit.

Undo: `git revert <that commit>`.

## What inference covers

Delete these lines when you translate. The values come from validators and columns.

| factory_bot line | Why it is redundant |
| --- | --- |
| `name { Faker::Name.name }`, `title { Faker::Lorem.sentence }` | Strings come from FFaker, shaped by name |
| `email { Faker::Internet.email }` | Email-named attributes get a plausible address, and a format validator is honored |
| `sequence(:email)` on a uniqueness-validated column | Regenerated on collision, within the DB and one bake graph |
| `status { %w[a b].sample }` on an enum or `inclusion` | A valid member is picked |
| `age { 20 }` with `numericality` bounds | A number inside the bounds |
| `slug`/`key`/`label` strings | Get a random suffix, so they stay distinct |
| `url`, `host`, `ip`, `timezone`, `body` | Name-shaped values on reserved domains |
| `password { 'x' }` with `has_secure_password` | Virtual validated attribute, confirmation matched |
| `association :author` on a required `belongs_to` | Built automatically in `:required_only` |
| `created_at { Time.current }` | Columns with a default or without a requirement are left alone |
| `confirmed { false }` with a DB default | The default is kept |
| JSON columns | A Hash (or Array when the default says so) |

Keep a line when a test asserts on it, or when the model cannot validate without it.

## What stays a definition

| Situation | Why |
| --- | --- |
| A test asserts the exact value | Inference is random |
| A custom validator reads a registry or setting (providers, emoji, report sources) | Not discoverable |
| A format no regex generation can build | You supply the value |
| A cross-record rule (a follow exists, the voter is not the author) | App-specific setup |
| A validator reads a parent's **id** | `association :x, persist: true` |
| Edge that must not reuse the owner's own parent | `strategy: :fresh` |
| A side-effecting setter other than `*_remote_url` (those are left blank automatically, with a WARN) | `skip :setter_name` |
| A read-only view as a parent | `skip :instance`, set the natural key |
| A structured JSON payload | A block with the right shape |
| Cycle breakers in `:all` | `skip :children`, `owner { nil }` |

Real examples with the reason for each are in `docs/reports/smoke/20261119-final-mastodon-definitions.rb` and `20261119-final-discourse-definitions.rb`.

## What cannot be migrated mechanically

| factory_bot feature | Problem | What to do |
| --- | --- | --- |
| `build_stubbed` | No stubbed-persisted object exists. `bake` gives `persisted? == false` and `id == nil` | Report. If a test only needs a plausible object, `bake` may do, but that is a test change, so ask |
| `transient` attributes | No transient DSL. Locals work only inside `define`, not as call-site parameters (`create(:user, with_posts: 3)` has no parameter) | Report. A trait or `association :posts, count: 3` may replace a specific use |
| `after(:build)` / `after(:create)` / `before(:create)` | Definitions have no callback DSL | Report hooks that must run for every call. A single call can use a `bake` or `bake!` block after construction or persistence |
| `initialize_with { ... }` block | Only a Hash is accepted | A Hash if the block is simple. Otherwise report |
| `create_list(:x, 3) { \|x, i\| ... }` (a block that uses the index) | `Array.new(3) { }` can express it, but moving the block body is more than a rename | Report |
| Nested `factory` / `parent:` inheritance | A subclass uses its parent class's definition when it has none. A definition of its own replaces it (no merge) | Traits, or repeat the lines the subclass still needs |
| `FactoryBot.create(:x)` inside `before(:all)` or seeds | Data outlives the example | Same behavior, but check |
| Uniqueness through a literal in the factory | Literal values are not regenerated | Use a block, or inference |

Anything in this table that a test actually uses is a **blocker**. List it for the user with the file and line. Do not change the test to make the migration pass.

## Fabrication, machinist, fixtures, hand-rolled helpers

The same ground rules apply (isolation, renames only, doors, ask before deleting). Detail and before/after examples are in the skill: [`references/other-tools.md`](../../skills/factory-bakery-migrate/references/other-tools.md).

### Fabrication

| Fabrication | FactoryBakery |
| --- | --- |
| `Fabricator(:user) { name 'Ada' }` | `FactoryBakery.define(User) { name { 'Ada' } }` |
| `Fabricate(:user)` | `FactoryBakery.bake!(User)` |
| `Fabricate.build(:user)` | `FactoryBakery.bake(User)` |
| `Fabricate.times(3, :user)` | `Array.new(3) { FactoryBakery.bake!(User) }` |
| `Fabricate.attributes_for(:user)` | Helper |
| `after_build`, `after_create`, `transient` | Not supported |

### Machinist

| Machinist | FactoryBakery |
| --- | --- |
| `User.blueprint { name { 'Ada' } }` | `FactoryBakery.define(User) { name { 'Ada' } }` |
| `User.make` | `FactoryBakery.bake!(User)` |
| `User.make!` | `FactoryBakery.bake!(User)` |
| `User.make(:admin)` / `User.blueprint(:admin)` | A trait: `FactoryBakery.bake!(User, :admin)` |
| `User.plan` | Helper |
| `sn` serial numbers | Counter local |

(Machinist 1 `make` saves, Machinist 2 `make` builds and `make!` saves. Map each to `bake` or `bake!` accordingly.)

### Rails fixtures

Fixtures are shared, named, global data. FactoryBakery builds data per example. The two differ in kind, so a conversion changes tests (`users(:ada)` has no direct rename). That is outside the renames-only rule. Do **not** convert fixtures automatically. Report them, and let the user decide. If they choose to, convert one fixture file at a time and replace `users(:ada)` with a `let` that bakes with the fixture's distinguishing values. This is a one-way door. Ask first.

### Hand-rolled `create!` helpers

```ruby
def create_user(attrs = {})
  User.create!({ name: 'Ada', email: "u#{rand(99999)}@example.com" }.merge(attrs))
end
```

Replace the **body** of the helper, keep its name, so call sites do not change:

```ruby
def create_user(attrs = {})
  FactoryBakery.bake!(User, **attrs)
end
```

If the helper sets values a test asserts on, keep them in a definition. The helper's call sites remain unchanged, which satisfies the renames-only rule.

## Rollback

| Situation | Action |
| --- | --- |
| A batch of renames breaks the suite | `git revert` that commit, or `git checkout` the batch in the worktree |
| The whole migration is wrong | Remove the worktree and branch (see step 0). The main checkout was never touched |
| Deletion was a mistake | `git revert` the deletion commit |
