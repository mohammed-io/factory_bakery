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

      class << self
        def call(model_class, attr_name)
          new(model_class, attr_name).read
        end
      end

      def initialize(model_class, attr_name)
        @model_class = model_class
        @attr_name = attr_name.to_s
      end

      def read
        column = column_for(@model_class, @attr_name)
        validators = validators_for(@model_class, @attr_name)

        rules = fold_validators(validators)
        enum_attribute, enum_values = read_enum
        array_column = array_column?(column)

        ConstraintSet.new(
          model_class: @model_class,
          attr_name: @attr_name,
          type: array_column ? :array : column&.type,
          array_element_type: array_column ? array_element_type_for(column) : nil,
          db_limit: column&.limit,
          nullable: column&.null,
          has_default: !column&.default.nil?,
          precision: column&.precision,
          scale: column&.scale,
          column_backed: !column.nil?,
          column_backed_target: @model_class.respond_to?(:columns_hash),
          sti_discriminator: sti_discriminator?,
          min_length: rules.min_length,
          max_length: rules.max_length,
          exact_length: rules.exact_length,
          with_regexes: rules.with_regexes.freeze,
          without_regexes: rules.without_regexes.freeze,
          allowed_values: rules.allowed_values,
          forbidden_values: rules.forbidden_values,
          must_be_present: rules.must_be_present,
          absence_required: rules.absence_required,
          accept_value: rules.accept_value,
          enum_attribute: enum_attribute,
          enum_values: enum_values.freeze,
          has_validators: !validators.empty?,
          value_shaping: validators.any? { |validator| VALUE_SHAPING_VALIDATORS.include?(validator.class.name) },
          acceptance_validated: validators.any? do |validator|
            validator.instance_of?(ActiveModel::Validations::AcceptanceValidator)
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

        [value.first, value.last].any? { |bound| bound.is_a?(Float) }
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

      # [routing flag, values]: the flag mirrors enum membership detection,
      # the values mirror what the enum filler samples from. They are computed
      # independently exactly as the router and the filler each did before,
      # including their different fallback behavior.
      def read_enum
        [enum_attribute?, enum_values]
      end

      def enum_attribute?
        if @model_class.respond_to?(:defined_enums)
          @model_class.defined_enums.key?(@attr_name)
        elsif @model_class.respond_to?(:pluralized_enum_values)
          @model_class.pluralized_enum_values.key?(@attr_name.pluralize)
        else
          validators_for(@model_class, @attr_name).any? do |validator|
            validator.instance_of?(ActiveModel::Validations::InclusionValidator) &&
              Array(validator.options[:in]).all? { |value| value.is_a?(String) }
          end
        end
      end

      def enum_values
        values = []
        if @model_class.respond_to?(:defined_enums)
          values = @model_class.defined_enums[@attr_name]&.keys || []
        end

        if values.empty? && @model_class.respond_to?(:pluralized_enum_values)
          pluralized_name = @attr_name.pluralize
          values = @model_class.pluralized_enum_values[pluralized_name]&.keys || []
        end

        return values unless values.empty?

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
      # so a plain `type` column is still routed normally.
      def sti_discriminator?
        return false unless @model_class.respond_to?(:inheritance_column)

        column = @model_class.inheritance_column
        !column.to_s.empty? && @attr_name == column.to_s
      end

      # Targets without a schema expose no columns; targets without validators
      # expose no rules. Both lookups are optional so the reader runs on any
      # target that exposes the relevant information.
      def column_for(model_class, attr_name)
        return nil unless model_class.respond_to?(:columns_hash)

        model_class.columns_hash[attr_name.to_s]
      end

      def validators_for(model_class, attr_name)
        return [] unless model_class.respond_to?(:validators_on)

        model_class.validators_on(attr_name)
      end
    end
  end
end
