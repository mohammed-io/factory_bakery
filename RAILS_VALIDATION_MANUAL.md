# Rails Active Record Validations Reference

Reference for Rails validators relevant to generating test data values.

*Source: [Ruby on Rails Guides - Active Record Validations](https://guides.rubyonrails.org/active_record_validations.html)*

---

## Built-in Validators

### `absence`

Value must be blank (nil or empty string).

```ruby
validates :phone_number, absence: true
```

**Implication for generators:** Skip generating a value for this attribute.

---

### `acceptance`

Value must indicate acceptance (typically a checkbox).

```ruby
validates :terms_of_service, acceptance: true
validates :terms_of_service, acceptance: { accept: "yes" }
```

**Options:**

| Option | Default |
|--------|---------|
| `:accept` | `['1', true]` |

**Implication for generators:** Generate the accepted value (`'1'`, `true`, or custom `:accept` value).

---

### `confirmation`

Two fields must have identical content.

```ruby
validates :email, confirmation: true
```

**Options:**

| Option | Default |
|--------|---------|
| `:case_sensitive` | `true` |

**Implication for generators:** When generating a value for `email`, also generate the same value for `email_confirmation`.

---

### `comparison`

Value must satisfy a comparison with another attribute's value.

```ruby
validates :end_date, comparison: { greater_than: :start_date }
```

**Options:**

| Option | Description |
|--------|-------------|
| `:greater_than` | Value must be greater than supplied value |
| `:greater_than_or_equal_to` | Value must be >= supplied value |
| `:equal_to` | Value must equal supplied value |
| `:less_than` | Value must be less than supplied value |
| `:less_than_or_equal_to` | Value must be <= supplied value |
| `:other_than` | Value must be different from supplied value |

Each option accepts a value, proc, or symbol.

**Implication for generators:** Generate a value that satisfies the comparison constraint relative to another attribute.

---

### `format`

Value must match a regular expression.

```ruby
validates :legacy_code, format: { with: /\A[a-zA-Z]+\z/ }
```

**Options:**

| Option | Description |
|--------|-------------|
| `:with` | Regex that value must match |
| `:without` | Regex that value must NOT match |
| `:multiline` | Required if using `^` or `$` anchors |

**Implication for generators:** Generate a value that matches the `:with` regex (or avoids `:without` regex).

---

### `inclusion`

Value must be from a predefined set.

```ruby
validates :size, inclusion: { in: %w(small medium large) }
```

**Options:**

| Option | Aliases |
|--------|---------|
| `:in` | `:within` |

The set can be an array, range, proc, lambda, or symbol.

```ruby
# Dynamic set using proc
validates :size, inclusion: { in: ->(coffee) { coffee.available_sizes } }
```

**Implication for generators:** Pick a random value from the `:in` set.

---

### `exclusion`

Value must NOT be from a predefined set.

```ruby
validates :subdomain, exclusion: { in: %w(www us ca jp) }
```

**Options:** Same as `inclusion` (`:in`/`:within`)

**Implication for generators:** Generate a value, then ensure it's not in the excluded set.

---

### `length`

String length constraints.

```ruby
validates :name, length: { minimum: 2 }
validates :bio, length: { maximum: 500 }
validates :password, length: { in: 6..20 }
validates :code, length: { is: 8 }
```

**Options:**

| Option | Description |
|--------|-------------|
| `:minimum` | Value cannot be shorter than specified length |
| `:maximum` | Value cannot be longer than specified length |
| `:in` / `:within` | Length must be within range |
| `:is` | Length must equal exact value |

**Implication for generators:** Generate a value whose length satisfies the constraint.

---

### `numericality`

Value must be numeric with optional constraints.

```ruby
validates :points, numericality: true
validates :age, numericality: { only_integer: true, greater_than: 0 }
```

**Basic Options:**

| Option | Description |
|--------|-------------|
| `:only_integer` | Value must be an integer |
| `:only_numeric` | Value must be instance of `Numeric` |

**Constraint Options:**

| Option | Description |
|--------|-------------|
| `:greater_than` | Value must be greater than supplied value |
| `:greater_than_or_equal_to` | Value must be >= supplied value |
| `:equal_to` | Value must equal supplied value |
| `:less_than` | Value must be less than supplied value |
| `:less_than_or_equal_to` | Value must be <= supplied value |
| `:other_than` | Value must be different from supplied value |
| `:in` | Value must be in supplied range |
| `:odd` | Value must be odd |
| `:even` | Value must be even |

**Implication for generators:** Generate a numeric value satisfying all constraints.

---

### `presence`

Value must not be blank.

```ruby
validates :name, presence: true
```

**Implication for generators:** Always generate a non-blank value.

---

### `uniqueness`

Value must be unique in the database.

```ruby
validates :email, uniqueness: true
```

**Options:**

| Option | Description |
|--------|-------------|
| `:scope` | One or more attributes to limit uniqueness check |
| `:case_sensitive` | Whether uniqueness check is case-sensitive |
| `:conditions` | Additional WHERE clause as proc/lambda |

```ruby
validates :name, uniqueness: { scope: :year }
validates :name, uniqueness: { case_sensitive: false }
```

**Implication for generators:** Use unique generators (e.g., `FFaker::Internet.unique.email`).

---

## Common Validation Options

### `:allow_nil`

Skip validation when value is `nil`.

```ruby
validates :size, inclusion: { in: %w(small medium large) }, allow_nil: true
```

**Implication for generators:** May generate `nil` for this attribute.

### `:allow_blank`

Skip validation when value is blank (`nil` or empty string).

```ruby
validates :title, length: { is: 6 }, allow_blank: true
```

**Implication for generators:** May generate `nil` or empty string for this attribute.

### `:on`

Specify when validation should run.

```ruby
validates :email, uniqueness: true, on: :create
validates :age, numericality: true, on: :update
```

**Implication for generators:** Context-aware generation - may skip for certain contexts.

---

## Listing Validators

Inspect validators defined on a model.

```ruby
# All validators on a model
Person.validators

# Validators for a specific attribute
Person.validators_on(:email)
#=> [#<ActiveModel::Validations::UniquenessValidator:0x... @attributes=[:email]>]
```

Access validator options:

```ruby
Person.validators_on(:email).first.options
#=> { case_sensitive: true }
```

---

## Quick Reference Summary

| Validator | Key Options | Generator Action |
|-----------|-------------|------------------|
| `absence` | - | Skip generation |
| `acceptance` | `:accept` | Generate accepted value |
| `confirmation` | `:case_sensitive` | Copy value to `_confirmation` field |
| `comparison` | `:greater_than`, `:less_than`, etc. | Generate value satisfying constraint |
| `format` | `:with`, `:without` | Generate value matching regex |
| `inclusion` | `:in` / `:within` | Pick random from set |
| `exclusion` | `:in` / `:within` | Generate value not in set |
| `length` | `:minimum`, `:maximum`, `:in`, `:is` | Generate value with proper length |
| `numericality` | `:only_integer`, comparison options | Generate numeric value |
| `presence` | - | Always generate non-blank |
| `uniqueness` | `:scope`, `:case_sensitive` | Use unique generator |
