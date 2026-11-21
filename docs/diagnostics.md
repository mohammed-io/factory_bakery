# Doctor diagnostics

Run `bin/rails factory_bakery:doctor` to check all concrete Active Record models, or `bin/rails 'factory_bakery:doctor[Post,Admin::Post]'` for selected models. The task rolls back its database probes on the current role's registered Active Record connections. Model code still runs, including callbacks with effects outside those transactions.

## Unique value collisions

When FactoryBakery exhausts its unique-value retries, give the attribute a declaration that varies across bakes and satisfies the model's validators. For scoped uniqueness, check the generated values for the scope columns too.

## Association target

If FactoryBakery cannot discover a target, declare the association in the definition. For a polymorphic association, specify the concrete class with `association :target, factory: SomeClass`.

## Incomplete persistence

An associated record was generated but remained unsaved. Check its validations, callbacks, and the edge's autosave behavior. Give the associated model its own definition if it needs additional values to save.

## Database constraints

A NOT NULL or foreign-key violation means the database rejected an insert. Check the required column or reference against the actual database schema. Declare a value for the column or a valid association for the reference.

## Custom validation

Read the first reported model error and check the related validation or callback. A definition can supply values for invariants that depend on application code or a combination of attributes.
