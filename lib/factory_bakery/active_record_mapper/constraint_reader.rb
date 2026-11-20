# frozen_string_literal: true

module FactoryBakery
  module ActiveRecordMapper
    # The single place that reads a schema-backed or validator-bearing target
    # and normalizes everything the generators need into a ConstraintSet.
    # Schema facts come from columns_hash, validation rules from the target's
    # validators, enum membership from the target's enum registry. Fillers and
    # the routing policy consume the normalized result and never read the
    # target themselves.
    #
    # Raw option forms (literals, Procs, Symbols) are copied through unchanged:
    # they are data, resolved against the object being built at value-generation
    # time (see AttributeFillers::ValueResolution).
    class ConstraintReader
      # A defaulted or virtual column keeps its database default unless one of
      # these validators constrains the shape of the generated value (W1,
      # issue #41). Absence is deliberately excluded: it wants nil, which the
      # no-op filler already provides.
      VALUE_SHAPING_VALIDATORS = [
        'ActiveModel::Validations::PresenceValidator',
        'ActiveRecord::Validations::PresenceValidator',
        'ActiveModel::Validations::FormatValidator',
        'ActiveModel::Validations::LengthValidator',
        'ActiveRecord::Validations::LengthValidator',
        'ActiveRecord::Validations::UniquenessValidator',
        'ActiveModel::Validations::InclusionValidator',
        'ActiveModel::Validations::ExclusionValidator',
        'ActiveModel::Validations::NumericalityValidator',
        'ActiveRecord::Validations::NumericalityValidator',
        'ActiveModel::Validations::ComparisonValidator'
      ].freeze

      # Validators that cannot accept nil (length only when it asks for a
      # positive minimum). Uniqueness and comparison belong here too: Rails
      # treats a NULL duplicate as taken and a nil bound as an invalid
      # comparison, so a nullable column carrying either still needs a value.
      # Custom EachValidators deliberately never force a fill: their behaviour
      # is app-specific and may have side effects.
      NIL_REJECTING_VALIDATORS = [
        'ActiveModel::Validations::PresenceValidator',
        'ActiveRecord::Validations::PresenceValidator',
        'ActiveModel::Validations::InclusionValidator',
        'ActiveModel::Validations::FormatValidator',
        'ActiveModel::Validations::LengthValidator',
        'ActiveRecord::Validations::LengthValidator',
        'ActiveModel::Validations::NumericalityValidator',
        'ActiveRecord::Validations::NumericalityValidator',
        'ActiveModel::Validations::AcceptanceValidator',
        'ActiveRecord::Validations::AcceptanceValidator',
        'ActiveModel::Validations::ComparisonValidator',
        'ActiveRecord::Validations::UniquenessValidator'
      ].freeze

      # An attribute whose writer has side effects must never be handed a
      # heuristic value: Mastodon's Remotable defines `avatar_remote_url=`,
      # which downloads whatever URL it is assigned. The name pattern is
      # recognized here, beside every other schema/validation fact, and the
      # core routes it to a filler that leaves the attribute blank (ADR-0001).
      REMOTE_URL_WRITER_PATTERN = /(?:\A|_)remote_url\z|\Aremote_\w*url\z/

      class << self
        def call(model_class, attr_name, record = nil)
          new(model_class, attr_name, record).read
        end
      end

      def initialize(model_class, attr_name, record = nil)
        @model_class = model_class
        @attr_name = attr_name.to_s
        @record = record
      end

      def read
        column = column_for(@model_class, @attr_name)
        validators = validators_for(@model_class, @attr_name)

        rules = fold_validators(validators)
        enum_attribute, enum_values = read_enum(attribute_names(@model_class, @attr_name))
        array_column = array_column?(column)

        ConstraintSet.new(
          model_class: @model_class,
          attr_name: @attr_name,
          type: array_column ? :array : normalized_column_type(column),
          array_element_type: array_column ? array_element_type_for(column) : nil,
          db_limit: column&.limit,
          nullable: column&.null,
          has_default: !column&.default.nil?,
          default_value: column&.default,
          precision: column&.precision,
          scale: column&.scale,
          **shape_facts(column, rules),
          min_length: rules.min_length,
          max_length: rules.max_length,
          exact_length: rules.exact_length,
          with_regexes: rules.with_regexes.freeze,
          without_regexes: rules.without_regexes.freeze,
          allowed_values: rules.allowed_values,
          forbidden_values: rules.forbidden_values,
          must_be_present: rules.must_be_present,
          absence_required: rules.absence_required,
          nil_rejected: nil_rejecting?(validators),
          accept_value: rules.accept_value,
          enum_attribute: enum_attribute,
          enum_values: enum_values.freeze,
          has_validators: !validators.empty?,
          value_shaping: validators.any? { |validator| VALUE_SHAPING_VALIDATORS.include?(validator.class.name) },
          acceptance_validated: validators.any? do |validator|
            validator.instance_of?(ActiveModel::Validations::AcceptanceValidator)
          end,
          confirmation_validated: validators.any? do |validator|
            validator.instance_of?(ActiveModel::Validations::ConfirmationValidator)
          end,
          inclusion_validated: rules.inclusion_validated,
          first_inclusion_values: rules.first_inclusion_values,
          length_validated: rules.length_validated,
          format_validated: rules.format_validated,
          numericality_validated: rules.numericality_validated,
          numericality_only_integer: rules.numericality_only_integer,
          numericality_has_float_bound: rules.numericality_has_float_bound,
          numeric_bounds: rules.numeric_bounds,
          comparison_bounds: rules.comparison_bounds
        )
      end

      private

      # The target/attribute shape flags in one place: whether a column backs
      # the attribute, whether the target can expose schema facts at all,
      # whether the framework owns the attribute (STI), and which container
      # shape a JSON-backed value must take. Every fact is derived here, so
      # the core only ever sees plain values (ADR-0001).
      def shape_facts(column, rules)
        {
          column_backed: !column.nil?,
          column_backed_target: @model_class.respond_to?(:columns_hash),
          sti_discriminator: sti_discriminator?,
          json_shape: json_shape(column, rules.allowed_values),
          json_text: json_text?(column),
          guarded_writer: guarded_writer?
        }
      end

      # A text column an index casts to json/jsonb must hold a JSON document
      # (see JsonCast). Only plain text columns qualify: a real json/jsonb
      # column already routes to the JSON filler, and an Array-serialized
      # attribute needs the Array generator, so neither reaches the string
      # filler's JSON fallback.
      def json_text?(column)
        return false if column.nil?
        return false unless %i[string text].include?(column.type)

        MapperRegistry.json_text?(@model_class, @attr_name)
      end

      # A small mutable accumulator folded over the attribute's validators in
      # declaration order. Order matters: each validator class overwrites the
      # fields it owns, so two validators of the same kind resolve last-wins
      # and a comparison validator never resets parity set by a numericality
      # one.
      Rules = Struct.new(
        :min_length, :max_length, :exact_length,
        :with_regexes, :without_regexes,
        :allowed_values, :forbidden_values,
        :must_be_present, :absence_required,
        :accept_value,
        :inclusion_validated, :first_inclusion_values,
        :length_validated, :format_validated,
        :numericality_validated, :numericality_only_integer, :numericality_has_float_bound,
        :numeric_bounds, :comparison_bounds,
        keyword_init: true
      ) do
        def self.none
          new(
            with_regexes: [], without_regexes: [],
            must_be_present: false, absence_required: false,
            inclusion_validated: false, length_validated: false, format_validated: false,
            numericality_validated: false, numericality_only_integer: false, numericality_has_float_bound: false,
            numeric_bounds: ConstraintSet::Bounds.new, comparison_bounds: ConstraintSet::Bounds.new
          )
        end
      end
      private_constant :Rules

      def fold_validators(validators)
        validators.reduce(Rules.none) do |rules, validator|
          case validator.class.name
          when 'ActiveModel::Validations::InclusionValidator'
            # Keep the raw Rails option form. A Proc (or Symbol) is a lazy set:
            # wrapping it with Array() here would sample the Proc itself and
            # stringify it instead of evaluating it at value-generation time.
            rules.allowed_values = validator.options[:in]
            unless rules.inclusion_validated
              rules.inclusion_validated = true
              rules.first_inclusion_values = validator.options[:in]
            end
          when 'ActiveModel::Validations::ExclusionValidator'
            rules.forbidden_values = validator.options[:in]
          when 'ActiveModel::Validations::PresenceValidator', 'ActiveRecord::Validations::PresenceValidator'
            rules.must_be_present = true
          when 'ActiveModel::Validations::AbsenceValidator', 'ActiveRecord::Validations::AbsenceValidator'
            rules.absence_required = true
          when 'ActiveModel::Validations::LengthValidator', 'ActiveRecord::Validations::LengthValidator'
            rules.length_validated = true if validator.class.name == 'ActiveModel::Validations::LengthValidator'
            apply_length_validator(rules, validator.options)
          when 'ActiveModel::Validations::FormatValidator'
            rules.format_validated = true
            # An attribute can carry several format validators: keep every
            # regex so verification covers the full set.
            rules.with_regexes << validator.options[:with] if validator.options[:with]
            rules.without_regexes << validator.options[:without] if validator.options[:without]
          when 'ActiveModel::Validations::NumericalityValidator', 'ActiveRecord::Validations::NumericalityValidator'
            capture_numericality_routing(rules, validator.options) unless rules.numericality_validated
            apply_numericality_validator(rules, validator.options)
          when 'ActiveModel::Validations::ComparisonValidator'
            apply_comparison_validator(rules, validator.options)
          when 'ActiveModel::Validations::AcceptanceValidator', 'ActiveRecord::Validations::AcceptanceValidator'
            accept_opt = validator.options[:accept]
            # Handle array of accepted values (the default is ["1", true]).
            rules.accept_value = accept_opt.is_a?(Array) ? accept_opt.first : accept_opt
          end

          rules
        end
      end

      # A nullable column with no default is filled when an applicable
      # validator rejects nil. `allow_nil` / `allow_blank` relax that, and a
      # length validator only rejects nil when it sets a positive minimum.
      def nil_rejecting?(validators)
        validators.any? { |validator| nil_rejecting_validator?(validator) }
      end

      def nil_rejecting_validator?(validator)
        return false unless NIL_REJECTING_VALIDATORS.include?(validator.class.name)
        return false if validator.options[:allow_nil] || validator.options[:allow_blank]

        return length_rejects_nil?(validator) if validator.class.name.include?('LengthValidator')

        true
      end

      def length_rejects_nil?(validator)
        opts = validator.options
        minimum = opts[:minimum] || opts[:is] || opts[:in]&.first
        # A lazy bound cannot be resolved while reading class-level rules;
        # treat it as a real requirement and let the filler resolve it.
        return true if minimum.is_a?(Proc) || minimum.is_a?(Symbol)

        minimum.to_i.positive?
      end

      def apply_length_validator(rules, opts)
        rules.min_length = opts[:minimum]
        rules.max_length = opts[:maximum]
        rules.exact_length = opts[:is]
        rules.min_length ||= opts[:in]&.first
        rules.max_length ||= opts[:in]&.last
      end

      def apply_numericality_validator(rules, opts)
        bounds = rules.numeric_bounds
        bounds.greater_than = opts[:greater_than]
        bounds.greater_than_or_equal_to = opts[:greater_than_or_equal_to]
        bounds.equal_to = opts[:equal_to]
        bounds.less_than = opts[:less_than]
        bounds.less_than_or_equal_to = opts[:less_than_or_equal_to]
        bounds.other_than = opts[:other_than]
        bounds.odd = opts[:odd] || false
        bounds.even = opts[:even] || false
        bounds.in_range = opts[:in]
      end

      # A comparison validator writes the same numeric fields (integer and
      # float generators consume them too) and the temporal comparison fields
      # (date and datetime generators consume those alone). It never touches
      # parity, and it only claims an in-range when one was given.
      def apply_comparison_validator(rules, opts)
        numeric = rules.numeric_bounds
        numeric.greater_than = opts[:greater_than]
        numeric.greater_than_or_equal_to = opts[:greater_than_or_equal_to]
        numeric.equal_to = opts[:equal_to]
        numeric.less_than = opts[:less_than]
        numeric.less_than_or_equal_to = opts[:less_than_or_equal_to]
        numeric.other_than = opts[:other_than]
        numeric.in_range = opts[:in] if opts[:in]

        comparison = rules.comparison_bounds
        comparison.greater_than = opts[:greater_than]
        comparison.greater_than_or_equal_to = opts[:greater_than_or_equal_to]
        comparison.equal_to = opts[:equal_to]
        comparison.less_than = opts[:less_than]
        comparison.less_than_or_equal_to = opts[:less_than_or_equal_to]
        comparison.other_than = opts[:other_than]
      end

      # Routing hint captured from the first numericality validator: integer
      # columns stay integer; a float bound anywhere routes to the float
      # generator.
      def capture_numericality_routing(rules, opts)
        rules.numericality_validated = true
        rules.numericality_only_integer = opts[:only_integer] ? true : false
        comparison_values = [
          opts[:greater_than], opts[:greater_than_or_equal_to], opts[:equal_to],
          opts[:less_than], opts[:less_than_or_equal_to], opts[:other_than],
          opts[:in]
        ].compact
        rules.numericality_has_float_bound = comparison_values.any? { |value| float_value?(value) }
      end

      def float_value?(value)
        return true if value.is_a?(Float)
        return false unless value.is_a?(Range)

        # `begin`/`end` stay nil on open ranges, unlike `first`/`last` which
        # raise; either endpoint being a Float routes to the float generator.
        [value.begin, value.end].any? { |bound| bound.is_a?(Float) }
      end

      # A text-castable type with no registered cast type (PostgreSQL's
      # tsvector, for instance) reports a nil `type` but still has a `sql_type`.
      # Normalize that into a plain symbol here so core routing can use it
      # without ever reading a framework class (ADR-0001). Types with a real
      # cast type are passed through unchanged.
      def normalized_column_type(column)
        return nil unless column
        return column.type if column.type

        sql_type = column.sql_type if column.respond_to?(:sql_type)
        return nil unless sql_type.is_a?(String) && !sql_type.empty?

        sql_type.to_sym
      end

      # PostgreSQL array columns expose array-ness on the column object; the
      # mapper is the only layer allowed to read it. The core sees a normalized
      # :array type and a plain-symbol element hint derived from the column's
      # underlying element type (sql_type/subtype).
      def array_column?(column)
        !column.nil? && column.respond_to?(:array?) && column.array?
      end

      def array_element_type_for(column)
        case column.type
        when :integer, :bigint, :smallint then :integer
        when :float, :decimal then :float
        when :boolean then :boolean
        else :string
        end
      end

      # A JSON-backed attribute may be expected to hold an Array rather than a
      # Hash. Three class-level facts say so, and reading them here keeps the
      # core on a plain symbol (ADR-0001):
      #   * the column's default is an Array (`t.json :blocks, default: []`);
      #   * the attribute is serialized with an Array coder
      #     (`serialize :tags, type: Array`);
      #   * an inclusion set whose members are Arrays constrains the whole
      #     value to an Array.
      def json_shape(column, allowed_values)
        return :array if array_default?(column)
        return :array if array_serialized_attribute?
        return :array if array_allowed_values?(allowed_values)

        :hash
      end

      # `column.default` keeps the raw SQL literal (the String "[]" for a
      # json array), so the default is read the way the framework casts it:
      # through the class's type-cast defaults, where it is a real Array.
      def array_default?(column)
        return false unless column

        typecast_default(column).is_a?(Array)
      end

      def typecast_default(column)
        return column.default unless @model_class.respond_to?(:column_defaults)

        @model_class.column_defaults.fetch(column_name_for(@model_class, @attr_name), column.default)
      end

      def array_serialized_attribute?
        return false unless @model_class.respond_to?(:attribute_types)

        serialized_array?(attribute_type)
      end

      def attribute_type
        types = @model_class.attribute_types
        types[column_name_for(@model_class, @attr_name)] || types[@attr_name]
      end

      # Duck-typed on purpose: the framework's serialized type exposes the
      # coder it round-trips through, and that coder knows which class it
      # holds. No framework constant is named here.
      def serialized_array?(type)
        coder = type.respond_to?(:coder) ? type.coder : nil
        coder.respond_to?(:object_class) && coder.object_class == Array
      rescue StandardError
        false
      end

      def array_allowed_values?(allowed_values)
        return false unless allowed_values.is_a?(Array)

        allowed_values.any? { |value| value.is_a?(Array) }
      end

      # An attribute whose writer has side effects must never be handed a
      # heuristic value (see REMOTE_URL_WRITER_PATTERN).
      def guarded_writer?
        REMOTE_URL_WRITER_PATTERN.match?(@attr_name)
      end

      # [routing flag, values]: the flag mirrors enum membership detection,
      # the values mirror what the enum filler samples from. Both look at every
      # name the attribute answers to: an enum declared on an `alias_attribute`
      # is registered under the alias, not under the column (issue #61).
      def read_enum(names)
        [enum_attribute?(names), enum_values(names)]
      end

      def enum_attribute?(names)
        return defined_enum?(names) if @model_class.respond_to?(:defined_enums)
        return pluralized_enum?(names) if @model_class.respond_to?(:pluralized_enum_values)

        inclusion_enum?
      end

      def defined_enum?(names)
        names.any? { |name| @model_class.defined_enums.key?(name) }
      end

      def pluralized_enum?(names)
        names.any? { |name| @model_class.pluralized_enum_values.key?(name.pluralize) }
      end

      # Schema-less targets express an enum as an inclusion of strings.
      def inclusion_enum?
        validators_for(@model_class, @attr_name).any? do |validator|
          validator.instance_of?(ActiveModel::Validations::InclusionValidator) &&
            Array(validator.options[:in]).all? { |value| value.is_a?(String) }
        end
      end

      def enum_values(names)
        values = []
        if @model_class.respond_to?(:defined_enums)
          values = names.flat_map { |name| @model_class.defined_enums[name]&.keys || [] }
        end

        if values.empty? && @model_class.respond_to?(:pluralized_enum_values)
          values = names.flat_map { |name| @model_class.pluralized_enum_values[name.pluralize]&.keys || [] }
        end

        return values.uniq unless values.empty?

        validators_for(@model_class, @attr_name).each do |validator|
          next unless validator.instance_of?(ActiveModel::Validations::InclusionValidator)

          option = validator.options[:in]
          if option.is_a?(Array) && option.all? { |value| value.is_a?(String) }
            values = option
            break
          end
        end

        values
      end

      # The STI discriminator is owned by the framework: `new` assigns the
      # subclass's name into the inheritance column and a faked value would
      # make a persisted row unloadable. Disabling STI empties the column name,
      # so a plain `type` column is still routed normally. Only a real
      # inheritance column is guarded: `alias_attribute :type, :other_column`
      # leaves `other_column` fillable (issue #61).
      def sti_discriminator?
        return false unless @model_class.respond_to?(:inheritance_column)

        column = @model_class.inheritance_column.to_s
        return false if column.empty?
        return false unless @model_class.respond_to?(:columns_hash)
        return false unless @model_class.columns_hash.key?(column)

        @attr_name == column
      end

      # Targets without a schema expose no columns; targets without validators
      # expose no rules. Both lookups are optional so the reader runs on any
      # target that exposes the relevant information. An alias is a second
      # spelling of its column, so either name reads the same schema facts.
      def column_for(model_class, attr_name)
        return nil unless model_class.respond_to?(:columns_hash)

        model_class.columns_hash[column_name_for(model_class, attr_name)]
      end

      def column_name_for(model_class, attr_name)
        return attr_name.to_s unless model_class.respond_to?(:attribute_aliases)

        model_class.attribute_aliases.fetch(attr_name.to_s, attr_name.to_s)
      end

      # The attribute's own name plus the name it resolves to and every alias
      # of that column (`alias_attribute` maps one way only).
      def attribute_names(model_class, attr_name)
        name = attr_name.to_s
        return [name] unless model_class.respond_to?(:attribute_aliases)

        aliases = model_class.attribute_aliases
        column = aliases.fetch(name, name)
        [name, column, *aliases.filter_map { |alias_name, target| alias_name if target == column }].uniq
      end

      def validators_for(model_class, attr_name)
        return [] unless model_class.respond_to?(:validators_on)

        validators = model_class.validators_on(attr_name)
        return validators unless @record

        validators.select { |validator| Conditional.applies?(validator, @record, @attr_name) }
      end
    end
  end
end
