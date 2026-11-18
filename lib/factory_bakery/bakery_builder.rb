# frozen_string_literal: true

module FactoryBakery
  class BakeryBuilder
    class BuildingInProgress < StandardError; end

    def initialize(model_klass, builder_proc = nil)
      @model_klass = model_klass
      @builder_proc = builder_proc

      @methods_to_be_called_on_object = []
      @traits = {}
    end

    @definitions = {}

    # A registered factory: its declaration block and the class explicitly
    # bound to it when declared with `klass:`.
    Definition = Struct.new(:builder_proc, :klass)

    class << self
      attr_reader :definitions

      # Registers a definition under a class or a symbol name. Class and symbol
      # keys are independent, and re-registering a key overwrites it so
      # definition files can be reloaded safely.
      def register(target, klass: nil, &blk)
        definitions[target] = Definition.new(blk, klass)
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
              "Could not resolve a class for factory #{symbol.inspect} (tried #{name.inspect}); pass klass: when defining it"
      end
    end

    def initialize_with(attributes)
      @initialize_with_attributes = attributes
    end

    def trait(trait_name, &blk)
      @traits[trait_name] = blk
    end

    def build(overrides: {}, traits: [])
      raise BuildingInProgress if @build_is_in_progress

      # Prevent recursive calls to build method.
      @build_is_in_progress = true

      evaluate_declarations(traits)

      object = instantiate
      apply_values(object, resolved_values(overrides), explicit_names(overrides))
      object
    ensure
      @build_is_in_progress = false
    end

    def method_missing(method_name, *, &block)
      # Defer attribute blocks so they run once per build, after the whole
      # definition block has registered traits and initialize_with.
      @methods_to_be_called_on_object << [method_name, block]
    end

    private

    def evaluate_declarations(traits)
      @methods_to_be_called_on_object = []
      instance_eval(&@builder_proc) if @builder_proc

      # Traits are appended after the base declarations and applied in the
      # order requested, so later assignments win for duplicate attributes.
      traits.each do |name|
        unless @traits.key?(name)
          raise FactoryBakery::Error, "Trait #{name.inspect} is not declared for #{@model_klass}"
        end

        instance_eval(&@traits[name])
      end
    end

    def instantiate
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
      @initialize_with_attributes.each_with_object({}) do |(name, value), attributes|
        attributes[name.to_sym] = value
      end
    end

    # POROs whose constructor takes no arguments receive their initialize_with
    # values through setters, just like declared attributes.
    def build_with_setters
      object = @model_klass.new
      normalize_keys(@initialize_with_attributes).each do |name, value|
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
    def resolved_values(overrides)
      normalized_overrides = normalize_keys(overrides)
      groups = alias_groups
      winning_declarations = declared_values(normalized_overrides, groups)

      heuristic_values(suppressed_names(normalized_overrides, groups))
        .merge(counter_cache_values)
        .merge(winning_declarations)
        .merge(normalized_overrides)
    end

    def explicit_names(overrides)
      declared_names + normalize_keys(overrides).keys
    end

    # Lazily derived alias groups. Each member maps to the full set; attributes
    # outside any group (and every attribute of a PORO, which has no
    # reflections) are their own singleton group and resolve exactly as before.
    def alias_groups
      return {} unless @model_klass.respond_to?(:reflect_on_all_associations)

      @model_klass.reflect_on_all_associations(:belongs_to).each_with_object({}) do |reflection, groups|
        members = [reflection.name.to_s, *Array(reflection.foreign_key).map(&:to_s)]
        members << reflection.foreign_type.to_s if reflection.polymorphic?
        members.uniq!
        members.each { |member| groups[member] = members }
      end
    end

    # A group taken by a declaration, an override or initialize_with suppresses
    # every heuristic member of that group, not just the member that was named.
    # Columns behind a belongs_to are always skipped (see belongs_to_column_names),
    # and Rails-maintained counter caches are never randomly filled either.
    def suppressed_names(overrides, groups)
      names = declared_names + overrides.keys + normalize_keys(@initialize_with_attributes).keys
      (names.flat_map { |name| groups.fetch(name, [name]) } + belongs_to_column_names +
        counter_cache_column_names).uniq
    end

    def heuristic_values(skip)
      candidate_attribute_names.each_with_object({}) do |attribute_name, values|
        next if column_backed? && attribute_name == @model_klass.primary_key.to_s
        next if skip.include?(attribute_name)

        filler = AttributeFillers::FillerSelector.new(@model_klass, attribute_name).call
        next if heuristic_skip?(filler)

        values[attribute_name] = filler.call
      end
    end

    def skipped_attribute_names
      declared_names + normalize_keys(@initialize_with_attributes).keys + counter_cache_column_names
    end

    def counter_cache_column_names
      @counter_cache_column_names ||= column_backed? ? CounterCacheDetector.new(@model_klass).column_names : []
    end

    # Rails maintains counter caches, so they are never randomly filled. A
    # database default (and a naturally nil nullable column) is left untouched;
    # a NOT NULL counter without a default becomes 0. This sits in the heuristic
    # layer, so declarations and overrides still win.
    def counter_cache_values
      explicitly_set = declared_names + normalize_keys(@initialize_with_attributes).keys

      counter_cache_column_names.each_with_object({}) do |name, values|
        next if explicitly_set.include?(name)

        column = @model_klass.columns_hash[name]
        values[name] = 0 if column && !column.null && column.default.nil?
      end
    end

    def heuristic_skip?(filler)
      filler.is_a?(AttributeFillers::NoopFiller) ||
        filler.is_a?(AttributeFillers::ConfirmationFiller)
    end

    def column_backed?
      @model_klass.respond_to?(:columns_hash)
    end

    # Columns behind a belongs_to cannot be guessed: a random FK dangles
    # against a real DB constraint, and a random polymorphic type is not a
    # constant. Leave them nil so declarations and overrides are the only
    # source of a value. POROs expose no reflections, so they are unaffected.
    # `foreign_key` is an array for composite FKs and a string otherwise.
    def belongs_to_column_names
      return [] unless column_backed? && @model_klass.respond_to?(:reflect_on_all_associations)

      @model_klass.reflect_on_all_associations(:belongs_to).flat_map do |reflection|
        names = Array(reflection.foreign_key).map(&:to_s)
        names << reflection.foreign_type.to_s if reflection.polymorphic?
        names
      end
    end

    # ActiveRecord targets enumerate their columns. POROs have no schema, so
    # the only attributes that can carry heuristic information are the ones
    # their validators declare.
    def candidate_attribute_names
      return @model_klass.columns_hash.keys.map(&:to_s) if column_backed?

      validator_attribute_names
    end

    def validator_attribute_names
      return [] unless @model_klass.respond_to?(:validators)

      @model_klass.validators.flat_map do |validator|
        names = Array(validator.attributes).map(&:to_s)
        class_name = validator.class.name
        if class_name == 'ActiveModel::Validations::ConfirmationValidator'
          names + names.map { |name| "#{name}_confirmation" }
        else
          names
        end
      end.uniq
    end

    # Only winning declarations are evaluated: a losing block's value would be
    # discarded, and the block may have side effects (e.g. an INSERT via bake!).
    # Declaration order is base, then traits in application order, so the last
    # declaration in a group wins. A call-site override of any group member
    # suppresses every declaration in that group. Plain declarations without a
    # block carry no value, so they never shadow an earlier block.
    def declared_values(overrides, groups)
      overridden_groups = overrides.keys.map { |name| groups.fetch(name, [name]) }.uniq

      declaration_winners(overridden_groups, groups).each_with_object({}) do |(_group, (name, block)), values|
        values[name] = block.call
      end
    end

    # Declaration order is base, then traits in application order, so the last
    # declaration in a group is its winner.
    def declaration_winners(overridden_groups, groups)
      @methods_to_be_called_on_object.each_with_object({}) do |(name, block), result|
        next unless block

        group = groups.fetch(name.to_s, [name.to_s])
        next if overridden_groups.include?(group)

        result[group] = [name.to_s, block]
      end
    end

    def declared_names
      @methods_to_be_called_on_object.map { |name, _| name.to_s }
    end

    def apply_values(object, values, reserved)
      values.each do |name, value|
        setter = "#{name}="
        object.public_send(setter, value) if object.respond_to?(setter)
      end

      apply_confirmations(object, reserved)
    end

    def apply_confirmations(object, reserved)
      candidate_attribute_names.each do |attribute_name|
        next if reserved.include?(attribute_name)

        filler = AttributeFillers::FillerSelector.new(@model_klass, attribute_name).call
        next unless filler.is_a?(AttributeFillers::ConfirmationFiller)

        source_name = attribute_name.sub(/_confirmation$/, '')
        source_value = object.public_send(source_name) if object.respond_to?(source_name)
        setter = "#{attribute_name}="
        object.public_send(setter, source_value) if object.respond_to?(setter)
      end
    end

    def normalize_keys(hash)
      (hash || {}).transform_keys(&:to_s)
    end
  end
end
