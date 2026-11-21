# Setup troubleshooting

For an error raised by a bake, use the [`factory-bakery-diagnostics`](../../factory-bakery-diagnostics/SKILL.md) skill and its [catalog](../../factory-bakery-diagnostics/references/diagnostics.md). This page covers problems with the setup itself.

| Symptom | Cause | Fix |
| --- | --- | --- |
| `NameError: uninitialized constant FactoryBakery` | Gem not in the bundle for this environment | Check the Gemfile group. Run `bundle install`. Run the command with the right `RAILS_ENV` |
| `cannot load such file -- factory_bakery/associations` | Old gem version, or not bundled | `bundle update factory_bakery`. Check `bundle exec` |
| `` `association` requires the associations plugin: require 'factory_bakery/associations' `` | Plugin not enabled | Add `config.factory_bakery.associations = {...}` (Rails) or the require |
| Definitions never apply | Wrong directory. `FactoryBakery.definition_paths` is empty or points elsewhere | Print it. Create the directory. Set `config.factory_bakery.definition_paths` |
| Definitions apply twice or `NoMethodError` at boot | factory_bot and FactoryBakery both load `spec/factories` | Separate directory: `spec/bakery` plus `definition_paths` |
| `bake` is undefined in tests | `FactoryBakery::Methods` not included | See [test-wiring.md](test-wiring.md), or call `FactoryBakery.bake` |
| Attachments are not attached | Attachments plugin not required | `require 'factory_bakery/attachments'` |
| Sequel model gets no auto-built associations | Not supported for Sequel | Assign in an attribute block |
| `factory_bakery:doctor` is not found | The installed gem predates the rake tasks | Update the gem, or skip the doctor step and bake models by hand <!-- verify against implementation --> |
| Boot is slow or loads all models | A polymorphic edge triggered `eager_load!` | Set `eager_load: false`, or declare the polymorphic target |
| Definitions are ignored after reload | Class-keyed definitions go stale | Re-run `FactoryBakery.find_definitions`, or use a symbol factory |
| Plugins vanish between examples | Something calls `FactoryBakery.reset_plugins!` | Do not call it in an app suite, or register again after |
| `ArgumentError` at boot naming an associations option | Wrong key or value in `config.factory_bakery.associations` | Valid keys: `mode`, `strategy`, `max_depth`, `default_count`, `eager_load` |

## Quick health check

```sh
bin/rails runner -e test '
  p version: FactoryBakery::VERSION,
    plugins: FactoryBakery::PluginRegistry.plugins.size,
    paths: FactoryBakery.definition_paths,
    mode: (FactoryBakery::Associations.mode if defined?(FactoryBakery::Associations))
'
```
