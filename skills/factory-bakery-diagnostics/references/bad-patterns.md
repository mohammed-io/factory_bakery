# Diagnosis bad patterns

Each entry: the pattern, why it hurts, what to do instead. Claims are checked against `lib/`, `docs/guide/` and the [catalog](diagnostics.md).

Contents: [change the model](#1-changing-validations-or-the-schema-to-make-baking-pass) · [retry until green](#2-retrying-until-green-instead-of-reproducing-with-the-seed) · [rescue](#3-rescuing-the-error) · [lines no rule needs](#4-adding-definition-lines-no-failing-rule-needs) · [skip a WARN](#5-adding-skip-to-silence-an-informational-warn) · [subclass definitions](#6-a-subclass-definition-that-copies-the-parent-or-forgetting-it-inherits) · [copying the drawn value](#7-copying-the-value-the-error-printed) · [raising max_bake_depth](#8-raising-max_bake_depth-to-cure-a-loop) · [scattershot options](#9-sprinkling-persist-fresh-or-skip-to-see-what-sticks) · [srand](#10-srand-to-stabilize-values) · [global fill_optional](#11-filling-every-optional-column-globally) · [unseeded randomness](#12-diagnosing-with-unseeded-randomness-left-in-the-blocks)

## 1. Changing validations or the schema to make baking pass

**Why it hurts.** It changes production behavior and data rules to suit a test tool. It is a one-way door the user did not approve, and a model rule almost always has a one-line definition answer.

```ruby
# bad: loosen the model so the factory passes
validates :provider, inclusion: { in: PROVIDERS + %w[bedrock] }

# good: tell the factory which value the rule accepts
FactoryBakery.define(LlmModel) { provider { LlmModel::OPEN_AI_PROVIDER_NAME } }
```

If a model really must change, say why and ask first.

## 2. Retrying until green instead of reproducing with the seed

**Why it hurts.** A record valid on some runs and invalid on others means a value drawn at random is rejected by a rule the gem cannot read. FactoryBakery does not retry, and the seed makes the draw repeatable. Re-running hides the bug until the unlucky seed returns. Hard-coding `FactoryBakery.seed = N` in the suite to dodge it fixes one draw and leaves the rule unanswered.

```sh
# bad
bundle exec rspec || bundle exec rspec

# good: the failure text names the seed and the bake number
bundle exec rspec --seed 12345
FACTORY_BAKERY_SEED=12345 RAILS_ENV=test bin/rails runner 'LlmModel.transaction(requires_new: true) { puts FactoryBakery.explain(FactoryBakery.bake(LlmModel)); raise ActiveRecord::Rollback }'
```

The runner draws bake #1 of `LlmModel`. When the failure says `bake #3 of LlmModel`, run two bakes first ([Replay it](../SKILL.md#1-reproduce)).

Then pin the value in a definition and check three seeds ([catalog](diagnostics.md#random-value-rejected-by-app-rule)).

## 3. Rescuing the error

**Why it hurts.** `rescue FactoryBakery::Error` or `rescue ActiveRecord::RecordInvalid` around a bake turns a precise diagnosis (message, class, seed, explanation) into a `nil` or a half-built record that fails later somewhere else. Doctor and the catalog read that message.

```ruby
# bad
record = begin
  FactoryBakery.bake!(Report)
rescue StandardError
  nil
end

# good: let it raise, read it, add the one definition line it names
FactoryBakery.define(Report) { source { 'core_report' } }
```

## 4. Adding definition lines no failing rule needs

**Why it hurts.** Two forms of one mistake. A guessed line nobody can justify stays forever, and the next reader cannot tell whether it matters. A line for the wrong attribute fixes nothing. Defining every attribute "to be safe" does the same in bulk: a declared value stops inference for that column, so a validator added later is no longer honored there, and the lines hide the few that matter. Both are invisible when wrong: a mistyped attribute name is skipped silently (the setter does not exist), so the line looks harmless and never errors. An attribute declared as `name 'x'` (no block) does raise: `Static attributes are unsupported; use name { "x" }`.

**Instead.** Read `FactoryBakery.explain(record)` or the `errors.full_messages`, find the validator, add exactly one line, delete it again to confirm the failure returns, and keep a comment only if the rule is not obvious. Declare what the model cannot bake without. A model that passes `factory_bakery:doctor` needs no definition. A test that asserts on a value passes it at the call site.

```ruby
# bad: guessed
FactoryBakery.define(Webhook) { events { ['x'] } }

# bad: every attribute, "to be safe"
FactoryBakery.define(User) do
  name { 'Ada' }
  email { 'ada@example.com' }
  age { 30 }
end

# good: the failing rule is a custom language validator
FactoryBakery.define(Follow) do
  languages { [] } # the language validator rejects random words
end

# good: the value one test depends on, at its call site
FactoryBakery.bake(User, email: 'ada@example.com')
```

A literal in a global definition also loses uniqueness regeneration: two bakes then collide ([unique-value-collisions](diagnostics.md#unique-value-collisions), [literal-override-uniqueness](diagnostics.md#literal-override-uniqueness)).

## 5. Adding `skip` to silence an informational WARN

**Why it hurts.** `left Account#avatar_remote_url blank on purpose` is logged once per model and attribute when the result is blank; a nonblank default survives without a warning. It records a skipped inferred assignment, not a proven-good bake: check the returned record or the exception for the result — a presence validation on the omitted attribute still fails `bake!`. The guarded-writer pattern (`remote_url`, `*_remote_url`, `remote_*url`) is an Active Record/Active Model mapper guard: left alone, the mapper never hands these writers a generated value. `skip` changes behavior — the setter is never called (it drops the empty-string assignment, and on a NOT NULL column without a default the bake then ends in `NotNullViolation` unless a presence validation raises `RecordInvalid` first), and `skip` on an association edge also suppresses its foreign key and type column — to remove one log line.

```ruby
# bad
FactoryBakery.define(Account) { skip :avatar_remote_url }

# good: nothing. To give it a value (and stub the HTTP call in the test):
FactoryBakery.bake(Account, avatar_remote_url: 'https://example.test/a.png')
```

Reserve `skip` for a setter with a side effect that is not a `*_remote_url` writer, a read-only view edge, or a cycle.

## 6. A subclass definition that copies the parent, or forgetting it inherits

**Why it hurts.** Two opposite mistakes.

- *Copying.* A class with no definition uses its nearest ancestor class's definition, traits included (`Object` is never searched). `Chat::NullUser < User` needs none. A copy drifts, and a subclass definition **replaces** the inherited one, so a half-copy silently drops lines and traits.
- *Forgetting.* A subclass bakes with its parent's values, and a stricter validation on it rejects them (common with STI) ([subclass-uses-parent-definition](diagnostics.md#subclass-uses-parent-definition)).

```ruby
# bad: a copy that adds nothing
FactoryBakery.define(Admin) { name { 'x' }; email { 'y' } }

# good: nothing, until Admin's own validation rejects User's values. Then write what Admin needs:
FactoryBakery.define(Admin) { name { 'x' }; role { 'admin' } }
```

## 7. Copying the value the error printed

**Why it hurts.** `Chosen at random: provider = "bedrock"` is the value that **failed**. The snippet below it uses a `{ nil }` placeholder with the comment `use a value your validations accept`. Pasting either unchanged keeps the bake invalid or sets a `nil`.

```ruby
# bad: the printed snippet, unedited
FactoryBakery.define(LlmModel) { provider { nil } }

# good
FactoryBakery.define(LlmModel) { provider { LlmModel::OPEN_AI_PROVIDER_NAME } }
```

## 8. Raising `max_bake_depth` to cure a loop

**Why it hurts.** `bake nesting exceeded max_bake_depth (10): User -> User -> User` shows the path where the limit was hit. A repeated class in it (as here) is a loop, usually a declaration block that bakes the class it belongs to. A higher limit only makes the loop longer before it fails. A path with no repetition is a deep graph, not a loop.

**Instead.** Check the path for a repeated class. If it repeats, break the loop (`skip :child`, or pass the owner into the nested bake). Raise the limit only for a legitimately deep graph ([nesting-too-deep](diagnostics.md#nesting-too-deep)).

## 9. Sprinkling `persist:`, `:fresh` or `skip` to see what sticks

**Why it hurts.** `persist: true` inserts and verifies a parent even under `bake`, `strategy: :fresh` is already the default, and `skip :edge` also removes the edge's foreign key. Each option answers one specific cause, and a wrong one can turn a visible error into a silent `nil` or an `IncompletePersistenceError`.

**Instead.** Match the cause to the fix with the catalog's [choosing the fix](diagnostics.md#choosing-the-fix) table: an id read by a validator needs `persist: true`, a reused parent that breaks a rule needs `:fresh` on that edge, a side effect or cycle needs `skip`.

## 10. `srand` to stabilize values

**Why it hurts.** The gem no longer draws from Ruby's global RNG, so `srand(seed)` does not make baked values repeat. The seed settings do ([Randomness](../../../docs/guide/configuration.md#randomness)).

```ruby
# bad
srand(1234)

# good, from the shell, for one replay
FACTORY_BAKERY_SEED=1234 bundle exec rspec spec/models/user_spec.rb
```

Relative dates (`1.day.ago`) still move with the clock, so a fixed seed does not freeze time-dependent failures.

## 11. Filling every optional column globally

**Why it hurts.** `FactoryBakery.fill_optional = true` fills every optional column of every model, so every bake exposes more validators and more values to reject. By default only what a valid record needs is filled, and an optional column left `nil` is expected.

```ruby
# bad: to fix one slug collision, fill every optional column of every model
FactoryBakery.fill_optional = true

# good: fill only the source of the derived value
FactoryBakery.bake(Post, fill_optional: [:title])
```

([derived-values-need-the-source](diagnostics.md#derived-values-need-the-source))

## 12. Diagnosing with unseeded randomness left in the blocks

**Why it hurts.** The seed covers what the gem draws, FFaker included. `Faker::`, `rand` and `SecureRandom` called from the project's own definition blocks are not seeded, so the same seed and bake order can still give different values. A replay that "passes" or "fails differently" then proves nothing about the seed.

```ruby
# bad: unseeded while diagnosing
username { "fb_#{SecureRandom.hex(5)}" }

# good: pin a literal for the replay, then restore the generator once the cause is found
username { 'fb_diag_1' }
```

If the line is the cause (a collision from a literal or a narrow generator), fix it as the catalog entry says.
