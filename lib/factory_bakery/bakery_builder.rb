# frozen_string_literal: true

module FactoryBakery
  # Collects a factory's DSL declarations and populates one model instance.
  class BakeryBuilder # rubocop:disable Metrics/ClassLength
    class BuildingInProgress < StandardError; end

    # Sentinel stored in the declaration stream for `skip :attribute`. It wins
    # and loses by the same rules as a value block, but contributes no value.
    OMITTED = Object.new.freeze

    attr_reader :heuristic_attribute_names

    def unchecked_heuristic_names
      heuristic_attribute_names - @read_heuristic_names
    end

    # Names filled only because optional filling was asked for: not required
    # for a valid record, not declared and not overridden. The verified
    # fallback reads it to tell a fill it may undo from one the caller decided.
    attr_reader :optional_candidates

    # Resetting a consumed fill would leave its dependent attributes stale.
    def resettable_optional_candidates
      Array(@optional_candidates) - @read_heuristic_names
    end

    # Signals for the verified fallback: an optional column was left to
    # heuristics, and leaving it unset could plausibly matter.
    def optional_candidates?
      !Array(@optional_candidates).empty?
    end

    def verification_needed?
      !!@verification_needed
    end

    def initialize(model_klass, builder_proc = nil, fill_optional: nil)
      @model_klass = model_klass
      @builder_proc = builder_proc
      @fill_optional = fill_optional

      @methods_to_be_called_on_object = []
      @traits = {}
      @heuristic_attribute_names = []
    end

    @definitions = {}

    # A registered factory: its declaration block and the class explicitly
    # bound to it when declared with `klass:`.
    Definition = Struct.new(:builder_proc, :klass)

    class << self
      attr_reader :definitions

      # The builder class for the plugins registered right now: this class with
      # the plugins' DSL module included. Extending every new builder with the
      # module created a singleton class per bake; the class is built once per
      # module instead, and is kept on the module so it goes away with it when
      # the registry rebuilds (a plugin registered or removed).
      def for_current_plugins
        scope = PluginRegistry.dsl_scope_module
        return self unless scope

        scope.instance_variable_get(:@factory_bakery_builder_class) ||
          scope.instance_variable_set(:@factory_bakery_builder_class, Class.new(self) { include scope })
      end

      # Registers a definition under a class or a symbol name. Class and symbol
      # keys are independent, and re-registering a key overwrites it so
      # definition files can be reloaded safely.
      def register(target, klass: nil, &blk)
        definitions[target] = Definition.new(blk, klass)
      end

      def declared_trait_names(target)
        definition = definitions[target]
        return [] unless definition&.builder_proc

        model = target.is_a?(Class) ? target : definition.klass
        builder_proc = definition.builder_proc
        declarations = for_current_plugins.new(model, builder_proc).instance_exec do
          record_layer(with_traits: true) { instance_eval(&builder_proc) }
        end
        declarations.trait_procs.keys.select { |name| name.is_a?(Symbol) }
      end

      # Normalizes a bake target into the class to instantiate and the
      # declaration block to apply. Classes bake with or without registration;
      # symbols must be registered and never fall back to constantization here.
      def resolve(target)
        case target
        when Class
          [target, definitions[target]&.builder_proc]
        when Symbol
          definition = definitions[target]
          raise FactoryBakery::Error, "No factory is registered for #{target.inspect}" unless definition

          [definition.klass || constantize(target), definition.builder_proc]
        else
          raise FactoryBakery::Error,
                "Unsupported bake target #{target.inspect}; pass a class or a registered symbol"
        end
      end

      private

      # Resolves :admin_user to AdminUser without eval. Called at bake time so
      # definition files can load before the model constants they name exist.
      # A missing constant is only ever reported as a clear error naming the
      # symbol; failures are not cached so a later bake can succeed.
      def constantize(symbol)
        name = symbol.to_s.split('_').map(&:capitalize).join
        Object.const_get(name)
      rescue NameError
        raise FactoryBakery::Error,
              "Could not resolve a class for factory #{symbol.inspect} (tried #{name.inspect}); " \
              'pass klass: when defining it'
      end
    end

    def initialize_with(attributes)
      # Its values are read as given, so a layer that sets them is not recorded.
      @layer_uncacheable = true
      @initialize_with_attributes = attributes
    end

    def trait(trait_name, &blk)
      @traits[trait_name] = blk
    end

    # An omission is a declaration like any other: it is recorded in the same
    # stream as value blocks, so a later trait replaces it and a call-site
    # override beats it by the ordinary precedence rules. Because its name is
    # a declared name, the whole alias group (association + FK + type) is
    # suppressed from heuristics and plugin auto-build, and no setter runs.
    def skip(*names)
      if names.empty? || block_given?
        raise FactoryBakery::Error,
              'skip is the attribute-omission DSL method; ' \
              'use add_attribute(:skip) { ... } to declare a real attribute named skip'
      end

      names.each { |name| @methods_to_be_called_on_object << [name, OMITTED] }
    end

    # Explicit form for an attribute whose name collides with a DSL method
    # (notably `skip`). It records exactly the same declaration as `name { }`.
    def add_attribute(name, &block)
      raise FactoryBakery::Error, "Use add_attribute(#{name.to_sym.inspect}) { ... } to declare a value" unless block

      @methods_to_be_called_on_object << [name, block]
    end

    def build(overrides: {}, traits: [])
      raise BuildingInProgress if @build_is_in_progress

      # Prevent recursive calls to build method.
      @build_is_in_progress = true
      @sibling_reads = {}
      @read_heuristic_names = []

      evaluate_declarations(traits)

      # One name-list snapshot for this build: every layer below reads from it
      # instead of re-deriving the same lists from the same inputs.
      @names = Names.new(
        declared: @declaration_set.names,
        plugin_declarations: @plugin_declarations,
        overrides: overrides,
        initialize_with: @initialize_with_attributes
      )

      object = instantiate
      BuildContext.building(object) do
        apply_values(object, resolved_values(overrides, object), explicit_names)
        run_after_instantiate(object)
      end
      object
    ensure
      @build_is_in_progress = false
    end

    # Declaration syntax accepts arbitrary names with blocks; it does not
    # expose those names as callable methods for introspection.
    def method_missing(method_name, *args, &block) # rubocop:disable Style/MissingRespondToMissing
      # A DSL name owned by an unloaded plugin must fail loudly rather than be
      # captured as an attribute declaration with a nil block.
      message = PluginRegistry.reserved_error_message(method_name)
      raise FactoryBakery::Error, message if message

      unless args.empty?
        example = args.length == 1 ? args.first.inspect : args.inspect
        raise FactoryBakery::Error, "Static attributes are unsupported; use #{method_name} { #{example} }"
      end

      unless block
        raise FactoryBakery::Error, "Use #{method_name} { ... } to declare a value, or skip #{method_name.inspect}"
      end

      # Defer attribute blocks so they run once per build, after the whole
      # definition block has registered traits and initialize_with.
      @methods_to_be_called_on_object << [method_name, block]
    end

    # Called by plugin DSL modules to record a declaration for the current
    # build. The registry knows which plugin's DSL method is executing, so the
    # entry lands in that plugin's own bucket and is handed back to its
    # after_instantiate hook.
    #
    # `reusable: true` promises the entry is frozen and holds nothing that
    # must be computed anew each bake, so the layer that declared it can be
    # recorded once and its entries replayed to later builds. Without the
    # promise, the layer is evaluated on every bake (ADR-0008).
    def record_plugin_declaration(entry, reusable: false)
      plugin = PluginRegistry.current
      raise FactoryBakery::Error, 'No plugin DSL call is in progress' unless plugin

      @layer_uncacheable = true unless reusable
      if @layer_plugin_entries
        @layer_plugin_entries << [plugin, entry]
      else
        plugin_declarations(plugin) << entry
      end
      entry
    end

    private

    # Leaves `@declaration_set` (the declarations of the base block followed by
    # the requested traits, in that order, so later assignments win for
    # duplicate attributes) and `@methods_to_be_called_on_object` for the rest
    # of the build. The definition's cache supplies each layer it already has;
    # the rest are recorded by running their block once (ADR-0008).
    def evaluate_declarations(traits)
      @plugin_declarations = Hash.new { |hash, plugin| hash[plugin] = [] }
      # A builder made through `for_current_plugins` already carries the DSL;
      # one made with `new` is extended here, at the cost of a singleton class.
      scope = PluginRegistry.dsl_scope_module
      extend(scope) if scope && !is_a?(scope)

      cache = DeclarationCache.for(@builder_proc)&.for_plugins(scope)
      @declaration_set = cache&.composed(traits) || collect_declarations(traits, cache)
      @methods_to_be_called_on_object = @declaration_set.pairs
      replay_plugin_entries(@declaration_set)
    end

    # Hands each plugin the entries its declarations made, in order, as if the
    # blocks had just run.
    def replay_plugin_entries(set)
      set.plugin_entries.each { |plugin, entry| plugin_declarations(plugin) << entry }
    end

    def collect_declarations(traits, cache)
      @all_layers_cacheable = true
      base = base_layer(cache)
      return base if traits.empty?

      @traits = base.trait_procs.dup
      layers = traits.map { |name| trait_layer(name, cache) }
      DeclarationSet.compose(base, layers).tap do |set|
        cache.store_composed(traits, set) if cache && @all_layers_cacheable
      end
    end

    def base_layer(cache)
      return DeclarationSet::EMPTY unless @builder_proc
      return cache.base if cache&.base

      @traits = {}
      remember(record_layer(with_traits: true) { instance_eval(&@builder_proc) }, cache, &:store_base)
    end

    def trait_layer(name, cache)
      raise FactoryBakery::Error, "Trait #{name.inspect} is not declared for #{@model_klass}" unless @traits.key?(name)
      return cache.trait(name) if cache&.trait(name)

      layer = record_layer { instance_eval(&@traits[name]) }
      remember(layer, cache) { |store, set| store.store_trait(name, set) }
    end

    # Runs one layer's block and returns what it declared as a DeclarationSet:
    # its attribute pairs, its plugin entries (collected here, and handed to
    # the build when the set is adopted) and, for a base layer, its traits.
    # The DSL calls that make a layer unsafe to reuse flag it while it runs.
    def record_layer(with_traits: false)
      @layer_uncacheable = false
      @methods_to_be_called_on_object = []
      @layer_plugin_entries = []
      yield
      DeclarationSet.new(@methods_to_be_called_on_object, trait_procs: with_traits ? @traits.dup : {},
                                                          plugin_entries: @layer_plugin_entries)
    ensure
      @layer_plugin_entries = nil
    end

    def remember(set, cache)
      @all_layers_cacheable &&= !@layer_uncacheable
      yield cache, set if cache && !@layer_uncacheable
      set
    end

    # Construction goes through the mapper so a framework whose models raise in
    # `new` (a raising default scope or an `after_initialize` callback) can
    # retry with fallbacks (issue #56). `apply` re-applies initialize_with
    # values when a fallback had to build the object without the constructor;
    # targets no mapper claims construct exactly as before.
    def instantiate
      FactoryBakery::MapperRegistry.construct(@model_klass, apply: method(:apply_initialize_with)) do
        construct_instance
      end
    end

    def construct_instance
      return @model_klass.new unless @initialize_with_attributes

      parameters = @model_klass.instance_method(:initialize).parameters
      return build_with_setters if parameters.empty?
      return @model_klass.new(**symbolized_initialize_with) if keyword_initializer?(parameters)

      @model_klass.new(@initialize_with_attributes)
    end

    def keyword_initializer?(parameters)
      parameters.all? { |type, _| %i[key keyreq keyrest].include?(type) }
    end

    def symbolized_initialize_with
      @initialize_with_attributes.transform_keys(&:to_sym)
    end

    # POROs whose constructor takes no arguments receive their initialize_with
    # values through setters, just like declared attributes.
    def build_with_setters
      apply_initialize_with(@model_klass.new)
    end

    # Assigns initialize_with values to an object built without them: an
    # argument-less constructor, or a record a construction fallback had to
    # build without running the constructor at all.
    def apply_initialize_with(object)
      @names.initialize_with.each do |name, value|
        setter = "#{name}="
        object.public_send(setter, value) if object.respond_to?(setter)
      end
      object
    end

    # Precedence: heuristics < declarations (base, then traits) < call-site overrides.
    #
    # An association name and the columns backing it (the FK, plus the type
    # column for a polymorphic association) form one alias group. The highest
    # layer mentioning any member wins the whole group; lower layers are dropped
    # before any block runs. Groups are derived from reflections at bake time so
    # definition files can still load before their models.
    def resolved_values(overrides, object)
      # Keep the in-progress record available to conditions and value fillers
      # while the explicit and generated values are resolved.
      BuildContext.with_record(object) { compute_resolved_values(overrides, object) }
    end

    def compute_resolved_values(_overrides, object)
      overrides = @names.overrides
      groups = alias_groups
      layer = nil
      heuristics = -> { layer ||= prepare_heuristics(overrides, groups, object) }
      declarations = resolve_declarations(overrides, groups, object, heuristics)
      finish_values(object, declarations, overrides, heuristics.call)
    end

    def resolve_declarations(overrides, groups, object, heuristics)
      blocks = winning_blocks(overrides, groups)
      declarations = DeclarationValues.new(self, object, blocks, sibling_names) do |name, resolved|
        next overrides[name] if overrides.key?(name)

        resolver, supplemental, skip = heuristics.call
        read_sibling(name, resolver, skip) do
          assign_values(object, supplemental.merge(resolved).merge(overrides))
          resolver.bind(resolved)
          declarations.bind_to(resolver)
        end
      end
      declarations.resolve_all
    end

    def sibling_names
      candidate_attribute_names + @names.raw_taken
    end

    def finish_values(object, declarations, overrides, layer)
      resolver, supplemental, skip = layer
      explicit = supplemental.merge(declarations).merge(overrides)
      assign_values(object, explicit)
      resolver.bind(declarations)
      generated = heuristic_values(skip, resolver)
      @heuristic_attribute_names = generated.keys
      generated.merge(explicit)
    end

    def prepare_heuristics(overrides, groups, object)
      supplemental, skip = heuristic_inputs(groups)
      # Constructor values are already assigned, and may have been transformed.
      bound_values = @names.initialize_with.merge(supplemental).merge(overrides)
      resolver = AttributeFillers::BakeTimeValues.new(@model_klass, bound_values, skip, object)
      [resolver, supplemental, skip]
    end

    def heuristic_inputs(groups)
      taken = publish_taken_names(groups)
      plugin_values = plugin_heuristic_values(taken, groups)
      plugin_skip = plugin_values.keys.flat_map { |name| groups.fetch(name, [name]) }
      skip = (suppressed_names(groups) + plugin_skip).uniq
      counters = counter_cache_values
      [counters.empty? ? plugin_values : counters.merge(plugin_values), skip.compact]
    end

    def publish_taken_names(groups)
      taken = taken_names(groups)
      context = BuildContext.current
      context.explicit_names = @names.raw_taken
      context.taken_names = taken
      taken
    end

    def read_sibling(name, resolver, skip)
      return @sibling_reads[name] if @sibling_reads.key?(name)

      yield
      resolver.value_for(name) if fill_sibling?(name, skip)
      stabilize_generated_sibling(name, resolver) if resolver.values.key?(name)

      value = sibling_value(name, resolver)
      resolver.bind(name => value)
      @sibling_reads[name] = value
    end

    def stabilize_generated_sibling(name, resolver)
      UniquenessEnforcer.new(resolver.object, [name]).call
      @read_heuristic_names << name
      value = resolver.object.public_send(name) if resolver.object.respond_to?(name)
      resolver.values[name] = value if FactoryBakery::MapperRegistry.uniqueness_validated?(@model_klass, name)
    end

    def sibling_value(name, resolver)
      return resolver.object.public_send(name) if resolver.object.respond_to?(name)

      resolver.assigned_value(name)
    end

    def fill_sibling?(name, skip)
      return false unless candidate_attribute_names.include?(name) && !skip.include?(name)

      FillOptional.full?(@fill_optional) || FillOptional.includes?(@fill_optional, name) ||
        RequiredAttribute.call(constraints_for(name))
    end

    def primary_key_name
      @model_klass.primary_key.to_s if column_backed?
    end

    # Names already decided at a higher layer (declarations, traits, overrides
    # and initialize_with), with alias groups expanded so a plugin never sees
    # just one spelling of an association. Plugin DSL declarations (for example
    # `association :account`) are declarations too, so they suppress heuristic
    # values such as :required_only auto-building just like plain attributes.
    def raw_taken_names
      @names.raw_taken
    end

    def taken_names(groups)
      raw_taken_names.flat_map { |name| groups.fetch(name.to_s, [name.to_s]) }.uniq
    end

    # Plugin values live in the heuristic layer. Plugins are consulted in
    # registration order; a later plugin wins on the same key. Within one alias
    # group the association name wins over its FK/type columns regardless of
    # hash insertion order.
    def plugin_heuristic_values(taken, groups)
      context = BuildContext.current
      supplied = PluginRegistry.plugins.each_with_object({}) do |plugin, all|
        next unless plugin.respond_to?(:heuristic_values)

        values = plugin.heuristic_values(@model_klass, context, taken)
        next unless values.respond_to?(:each_pair)

        normalize_keys(values).each do |name, value|
          all[name] = value unless taken.include?(name)
        end
      end

      suppress_plugin_aliases(supplied, groups)
    end

    def suppress_plugin_aliases(supplied, groups)
      association_names = belongs_to_association_names
      groups.each_value do |members|
        present = members.select { |member| supplied.key?(member) }
        winner = present.find { |member| association_names.include?(member) }
        next unless winner

        present.each { |member| supplied.delete(member) unless member == winner }
      end

      supplied
    end

    def belongs_to_association_names
      @belongs_to_association_names ||=
        FactoryBakery::MapperRegistry.belongs_to_association_names(@model_klass)
    end

    def plugin_declarations(plugin)
      (@plugin_declarations ||= Hash.new { |hash, key| hash[key] = [] })[plugin]
    end

    def run_after_instantiate(object)
      context = BuildContext.current
      PluginRegistry.plugins.each do |plugin|
        next unless plugin.respond_to?(:after_instantiate)

        plugin.after_instantiate(object, plugin_declarations(plugin), context)
      end
    end

    def explicit_names
      @names.explicit
    end

    # Lazily derived alias groups. Each member maps to the full set; attributes
    # outside any group (and every attribute of a target without associations)
    # are their own singleton group and resolve exactly as before.
    def alias_groups
      @alias_groups ||= FactoryBakery::MapperRegistry.alias_groups(@model_klass)
    end

    # A group taken by a declaration, an override or initialize_with suppresses
    # every heuristic member of that group, not just the member that was named.
    # Guard columns (foreign keys, polymorphic types, the STI discriminator,
    # the primary key and framework-maintained counters) are never filled
    # heuristically either.
    def suppressed_names(groups)
      names = @names.suppression_seeds
      (names.flat_map { |name| groups.fetch(name, [name]) } + guard_columns.names).uniq
    end

    def heuristic_values(skip, resolver)
      partition_candidates(skip).each do |name|
        resolver.value_for(name) unless @sibling_reads.key?(name)
      end
      resolver.values
    end

    # By default only attributes a valid record needs are generated. The
    # opt-in keeps the old "fill every column" behaviour, and a list opts in
    # just those names. Non-column-backed attributes (validator-declared
    # virtual names) follow the same rule: filled when an applicable validator
    # rejects nil, or when they carry acceptance or confirmation.
    #
    # Partitioning happens while the record is bound, so a condition-aware
    # rule is read for this bake rather than from the class-level cache. The
    # optional half doubles as the signal for the verified fallback (when it
    # is empty, a rebuild with everything filled cannot change the result) and
    # as the set of fills that may be undone when app validation rejects one,
    # so it is recorded in every mode.
    def partition_candidates(skip)
      fillable = candidate_attribute_names.reject { |name| skip.include?(name) }
      _, optional = fillable.partition { |name| RequiredAttribute.call(constraints_for(name)) }
      @optional_candidates = optional
      @verification_needed = needs_verification?(optional)
      return fillable if FillOptional.full?(@fill_optional)

      # A name on the opt-in list was asked for explicitly, so it is filled
      # here but is not an optional fill the fallback may undo.
      @optional_candidates = optional.reject { |name| FillOptional.includes?(@fill_optional, name) }
      fillable - @optional_candidates
    end

    # Only verify when leaving an optional column unset can plausibly matter:
    # a default that may fail a validator, or app validation the heuristics
    # cannot see. Otherwise the discovered constraints already guarantee the
    # lean record is valid, and running `valid?` would be needless work with
    # observable side effects (lazy validator procs).
    def needs_verification?(optional)
      optional.any? { |name| constrained_default?(constraints_for(name)) } ||
        FactoryBakery::MapperRegistry.custom_validation?(@model_klass)
    end

    def constrained_default?(constraints)
      constraints.has_default && constraints.has_validators
    end

    def constraints_for(name)
      FactoryBakery::MapperRegistry.constraints_for(@model_klass, name)
    end

    def guard_columns
      @guard_columns ||= FactoryBakery::MapperRegistry.guard_columns(@model_klass)
    end

    def counter_cache_column_names
      guard_columns.counter_names
    end

    # Framework-maintained counters are never randomly filled. A database
    # default (and a naturally nil nullable column) is left untouched; a NOT
    # NULL counter without a default becomes 0. This sits in the heuristic
    # layer, so declarations and overrides still win.
    def counter_cache_values
      counters = counter_cache_column_names
      return Names::EMPTY_HASH if counters.empty?

      explicitly_set = @names.declared + @names.init_with_keys
      counters.each_with_object({}) do |name, values|
        next if explicitly_set.include?(name)

        constraints = FactoryBakery::MapperRegistry.constraints_for(@model_klass, name)
        values[name] = 0 if constraints.column_backed && !constraints.nullable && !constraints.has_default
      end
    end

    # The mapper decides which attributes heuristics may consider: columns
    # for schema-backed targets, validator-declared names (plus their
    # confirmation twins) for validator-bearing ones.
    def candidate_attribute_names
      @candidate_attribute_names ||= FactoryBakery::MapperRegistry.attribute_universe(@model_klass)
    end

    # Only winning declarations are evaluated: a losing block's value would be
    # discarded, and the block may have side effects (e.g. an INSERT via bake!).
    # Declaration order is base, then traits in application order, so the last
    # declaration in a group wins. A call-site override of any group member
    # suppresses every declaration in that group.
    def winning_blocks(_overrides, groups)
      overridden_groups = @names.override_keys.map { |name| groups.fetch(name, [name]) }.uniq

      declaration_winners(overridden_groups, groups).each_with_object({}) do |(_group, (name, block)), values|
        next if block.equal?(OMITTED)

        values[name] = block
      end
    end

    # Declaration order is base, then traits in application order, so the last
    # declaration in a group is its winner.
    def declaration_winners(overridden_groups, groups)
      @methods_to_be_called_on_object.each_with_object({}) do |(name, block), result|
        group = groups.fetch(name.to_s, [name.to_s])
        next if overridden_groups.include?(group)

        result[group] = [name.to_s, block]
      end
    end

    def declared_names
      @names.declared
    end

    def apply_values(object, values, reserved)
      assign_values(object, values)
      apply_confirmations(object, reserved)
    end

    def assign_values(object, values)
      # Conditions read live attributes; a result cached before these setters
      # ran (for example a plugin guard checked ahead of call-site overrides)
      # no longer describes the record. Drop it rather than reusing it.
      BuildContext.invalidate_condition_results!
      values.each do |name, value|
        setter = "#{name}="
        object.public_send(setter, value) if object.respond_to?(setter)
      end
    end

    def apply_confirmations(object, reserved)
      candidate_attribute_names.each do |attribute_name|
        next if reserved.include?(attribute_name)

        filler = AttributeFillers::FillerSelector.cached_for(@model_klass, attribute_name)
        next unless filler.is_a?(AttributeFillers::ConfirmationFiller)

        source_name = attribute_name.sub(/_confirmation$/, '')
        source_value = object.public_send(source_name) if object.respond_to?(source_name)
        setter = "#{attribute_name}="
        object.public_send(setter, source_value) if object.respond_to?(setter)
      end
    end

    def normalize_keys(hash)
      return Names::EMPTY_HASH if hash.nil? || hash.empty?

      hash.transform_keys(&:to_s)
    end
  end
end
