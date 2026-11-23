# Diagnosis bad patterns

Each entry: the pattern, why it hurts, what to do instead. Claims are checked against `lib/`, `docs/guide/` and the [catalog](diagnostics.md).

Contents: [change the model](#1-changing-validations-or-the-schema-to-make-baking-pass) · [retry until green](#2-retrying-until-green-instead-of-reproducing-with-the-seed) · [rescue](#3-rescuing-the-error) · [blind definition line](#4-adding-a-definition-line-without-knowing-which-rule-needs-it) · [define everything](#5-defining-every-attribute-to-be-safe) · [skip a WARN](#6-adding-skip-to-silence-an-informational-warn) · [subclass definitions](#7-a-subclass-definition-that-copies-the-parent-or-forgetting-it-inherits) · [copying the drawn value](#8-copying-the-value-the-error-printed) · [raising max_bake_depth](#9-raising-max_bake_depth-to-cure-a-loop) · [scattershot options](#10-sprinkling-persist-fresh-or-skip-to-see-what-sticks) · [srand](#11-srand-to-stabilize-values) · [global fill_optional](#12-filling-every-optional-column-globally) · [editing one catalog copy](#13-editing-one-copy-of-the-catalog)

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
bundle exec rspec spec/models/llm_model_spec.rb --seed 12345
FACTORY_BAKERY_SEED=12345 bin/rails runner -e test 'puts FactoryBakery.explain(FactoryBakery.bake(LlmModel))'
```

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

## 4. Adding a definition line without knowing which rule needs it

**Why it hurts.** A line nobody can justify stays forever, and the next reader cannot tell whether it matters. A line for the wrong attribute fixes nothing, and a mistyped attribute name is skipped silently (the setter does not exist), so it even looks harmless.

**Instead.** Read `FactoryBakery.explain(record)` or the `errors.full_messages`, find the validator, add exactly one line, delete it again to confirm the failure returns, and keep a comment only if the rule is not obvious.

```ruby
# bad: guessed
FactoryBakery.define(Webhook) { events { ['x'] } }

# good: the failing rule is a custom language validator
FactoryBakery.define(Follow) do
  languages { [] } # the language validator rejects random words
end
```

## 5. Defining every attribute "to be safe"

**Why it hurts.** A definition for a column makes it a declared value: inference stops for it, so a validator added later is no longer honored for that column. The lines hide the few that matter, and a typo never errors. An attribute declared as `name 'x'` (no block) raises `Static attributes are unsupported; use name { "x" }`.

**Instead.** Declare what a test asserts on, or what the model cannot bake without. A model that passes `factory_bakery:doctor` needs no definition.

```ruby
# bad
FactoryBakery.define(User) do
  name { 'Ada' }
  email { 'ada@example.com' }
  age { 30 }
end

# good: only the value a test depends on
FactoryBakery.define(User) { email { 'ada@example.com' } }
```

A literal also loses uniqueness regeneration: two bakes then collide ([literal-override-uniqueness](diagnostics.md#literal-override-uniqueness)).

## 6. Adding `skip` to silence an informational WARN

**Why it hurts.** `left Account#avatar_remote_url blank on purpose` is logged once per model and attribute, and the bake **succeeded**. `skip` changes behavior (the setter is never called, and `skip` on an association edge also suppresses its foreign key and type column) to remove one log line.

```ruby
# bad
FactoryBakery.define(Account) { skip :avatar_remote_url }

# good: nothing. To give it a value (and stub the HTTP call in the test):
FactoryBakery.bake(Account, avatar_remote_url: 'https://example.test/a.png')
```

Reserve `skip` for a setter with a side effect that is not a `*_remote_url` writer, a read-only view edge, or a cycle.

## 7. A subclass definition that copies the parent, or forgetting it inherits

**Why it hurts.** Two opposite mistakes.

- *Copying.* A class with no definition uses its nearest ancestor class's definition, traits included (`Object` is never searched). `Chat::NullUser < User` needs none. A copy drifts, and a subclass definition **replaces** the inherited one, so a half-copy silently drops lines and traits.
- *Forgetting.* A subclass bakes with its parent's values, and a stricter validation on it rejects them (common with STI) ([subclass-uses-parent-definition](diagnostics.md#subclass-uses-parent-definition)).

```ruby
# bad: a copy that adds nothing
FactoryBakery.define(Admin) { name { 'x' }; email { 'y' } }

# good: nothing, until Admin's own validation rejects User's values. Then write what Admin needs:
FactoryBakery.define(Admin) { name { 'x' }; role { 'admin' } }
```

## 8. Copying the value the error printed

**Why it hurts.** `Chosen at random: provider = "bedrock"` is the value that **failed**. The snippet below it uses a `{ nil }` placeholder with the comment `use a value your validations accept`. Pasting either unchanged keeps the bake invalid or sets a `nil`.

```ruby
# bad: the printed snippet, unedited
FactoryBakery.define(LlmModel) { provider { nil } }

# good
FactoryBakery.define(LlmModel) { provider { LlmModel::OPEN_AI_PROVIDER_NAME } }
```

## 9. Raising `max_bake_depth` to cure a loop

**Why it hurts.** `bake nesting exceeded max_bake_depth (10): User -> User -> User` names a loop, usually a declaration block that bakes the class it belongs to. A higher limit only makes the loop longer before it fails.

**Instead.** Break the loop (`skip :child`, or pass the owner into the nested bake). Raise the limit only for a legitimately deep graph ([nesting-too-deep](diagnostics.md#nesting-too-deep)).

## 10. Sprinkling `persist:`, `:fresh` or `skip` to see what sticks

**Why it hurts.** `persist: true` inserts and verifies a parent even under `bake`, `strategy: :fresh` is already the default, and `skip :edge` also removes the edge's foreign key. Each option answers one specific cause, and a wrong one can turn a visible error into a silent `nil` or an `IncompletePersistenceError`.

**Instead.** Match the cause to the fix with the catalog's [choosing the fix](diagnostics.md#choosing-the-fix) table: an id read by a validator needs `persist: true`, a reused parent that breaks a rule needs `:fresh` on that edge, a side effect or cycle needs `skip`.

## 11. `srand` to stabilize values

**Why it hurts.** The gem no longer draws from Ruby's global RNG, so `srand(seed)` does not make baked values repeat. The seed settings do ([Randomness](../../../docs/guide/configuration.md#randomness)).

```ruby
# bad
srand(1234)

# good, from the shell, for one replay
FACTORY_BAKERY_SEED=1234 bundle exec rspec spec/models/user_spec.rb
```

Relative dates (`1.day.ago`) still move with the clock, so a fixed seed does not freeze time-dependent failures.

## 12. Filling every optional column globally

**Why it hurts.** `FactoryBakery.fill_optional = true` fills every optional column of every model, so every bake exposes more validators and more values to reject. By default only what a valid record needs is filled, and an optional column left `nil` is expected.

```ruby
# bad: a derived slug collides because the optional title is nil
FactoryBakery.fill_optional = true

# good: fill only the source of the derived value
FactoryBakery.bake(Post, fill_optional: [:title])
```

([derived-values-need-the-source](diagnostics.md#derived-values-need-the-source))

## 13. Editing one copy of the catalog

**Why it hurts.** `docs/diagnostics.md` and `skills/factory-bakery-diagnostics/references/diagnostics.md` must stay identical, apart from the note line and blank line at the top of the published copy. The doctor's links point at the published copy, and `spec/factory_bakery/diagnostics_catalog_spec.rb` fails when they differ or when a doctor hint names an anchor that does not exist.

**Instead.** Make every catalog edit in both files, then run `bundle exec rspec spec/factory_bakery/diagnostics_catalog_spec.rb`.
