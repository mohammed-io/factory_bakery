## [Unreleased]

## [0.0.2] - 2026-11-18

Complete rewrite of the gem. This release has no compatibility with v0.0.1 or earlier.

- Added heuristic fillers that build valid attribute values from ActiveModel validators and ActiveRecord column types (inclusion, exclusion, length, numericality, comparison, format, acceptance, confirmation, presence, absence, uniqueness hints, enums, and column defaults).
- Added `FactoryBakery.define` for reusable factory definitions with lazy attribute blocks, `trait` (including multiple traits per bake), `initialize_with`, named factories (`define(:name, klass: Model)` and lazy symbol-to-class resolution), and last-one-wins re-registration.
- Added `FactoryBakery.bake` (unsaved) and `FactoryBakery.bake!` (persists when supported), with call-site overrides taking precedence over traits and factory declarations.
- Added support for plain Ruby objects: setters are used for assignment, validator-driven heuristics apply to ActiveModel-compatible objects, attributes with no heuristic information stay `nil`, and `bake!` skips persistence for non-ActiveRecord targets.
- Added definition loading: Rails auto-loads from the first existing `spec/factories`, `test/factories`, or `factories` directory via a Railtie and `config.factory_bakery.definition_paths`; non-Rails apps use `FactoryBakery.definition_paths` and `FactoryBakery.find_definitions`.
- Added the opt-in `FactoryBakery::Methods` module with bare `bake` / `bake!` for RSpec and Minitest. No global functions are installed on `Object` or `Kernel`.
- Removed the generator-era internals and global API; the documented API is now `FactoryBakery.define`, `bake`, `bake!`, `find_definitions`, and `definition_paths`.
- Verified against Rails 7.1, 7.2, and 8.0 on Ruby 3.4.

## [0.1.0] - 2021-03-30

- Initial release
