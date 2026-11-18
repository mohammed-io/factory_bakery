# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    class FillerSelector
      attr_reader :model_class, :attr_name

      def initialize(model_class, attr_name)
        @model_class = model_class
        @attr_name = attr_name.to_s
      end

      def call
        # Priority 1: Confirmation attribute (e.g., password_confirmation)
        return confirmation_filler if confirmation_attribute?

        # Priority 2: Acceptance attribute
        return acceptance_filler if acceptance_attribute?

        # Rails owns the STI discriminator; never overwrite what `new` assigned.
        return noop_filler if sti_discriminator?

        # Non-ActiveRecord targets have no schema to route by. Use whatever
        # validator information the target exposes instead.
        return validator_routed_filler unless active_record_target?

        column_routed_filler
      end

      private

      def confirmation_attribute?
        attr_name.end_with?('_confirmation')
      end

      def acceptance_attribute?
        attr_name.end_with?('_accepted') ||
          validators_for(attr_name).any? do |v|
            v.instance_of?(ActiveModel::Validations::AcceptanceValidator)
          end
      end

      # Rails writes the subclass's sti_name into the inheritance column in
      # `new`; on the base class the value is left for the database. Faking it
      # would make a persisted row unloadable with ActiveRecord::SubclassNotFound.
      # Disabling STI sets inheritance_column to "", so a plain `type` column
      # is still routed to its normal filler.
      def sti_discriminator?
        return false unless model_class.respond_to?(:inheritance_column)

        column = model_class.inheritance_column
        !column.to_s.empty? && attr_name == column.to_s
      end

      def active_record_target?
        model_class.respond_to?(:columns_hash)
      end

      def validators_for(name)
        return [] unless model_class.respond_to?(:validators_on)

        model_class.validators_on(name)
      end

      def column_routed_filler
        column = model_class.columns_hash[attr_name]

        # Priority 3: Has default or virtual attribute -> Noop
        return noop_filler if has_default?(column) || virtual?(column)

        # Priority 4: Enum attribute
        return enum_filler if enum_attribute?

        # Priority 5: Type-based routing
        type_based_filler(column)
      end

      def validator_named?(validators, name)
        validators.any? do |validator|
          class_name = validator.class.name
          class_name == name
        end
      end

      # Route a schema-less target by the validators it declares. The attribute
      # universe is already limited to validator-covered names by the builder,
      # so no-information attributes never reach this path.
      def validator_routed_filler
        validators = validators_for(attr_name)
        return noop_filler if validators.empty?

        if (inclusion = find_validator(validators, 'ActiveModel::Validations::InclusionValidator'))
          return inclusion_based_filler(inclusion)
        end

        return string_filler if validator_named?(validators, 'ActiveModel::Validations::LengthValidator')
        return string_filler if validator_named?(validators, 'ActiveModel::Validations::FormatValidator')

        if (numericality = find_numericality_validator(validators))
          return numericality_filler(numericality)
        end

        # Presence, exclusion and other validators carry no value of their
        # own; a name-derived string is still a valid generated default.
        string_filler
      end

      def find_validator(validators, name)
        validators.find do |validator|
          class_name = validator.class.name
          class_name == name
        end
      end

      def find_numericality_validator(validators)
        find_validator(validators, 'ActiveModel::Validations::NumericalityValidator') ||
          find_validator(validators, 'ActiveRecord::Validations::NumericalityValidator')
      end

      def inclusion_based_filler(validator)
        values = Array(validator.options[:in])
        return noop_filler if values.empty?
        return integer_filler if values.all? { |value| value.is_a?(Integer) }
        return float_filler if values.all? { |value| value.is_a?(Numeric) }

        string_filler
      end

      def numericality_filler(validator)
        options = validator.options
        return integer_filler if options[:only_integer]

        comparison_values = [
          options[:greater_than], options[:greater_than_or_equal_to], options[:equal_to],
          options[:less_than], options[:less_than_or_equal_to], options[:other_than],
          options[:in]
        ].compact

        comparison_values.any? { |value| float_value?(value) } ? float_filler : integer_filler
      end

      def float_value?(value)
        return true if value.is_a?(Float)
        return false unless value.is_a?(Range)

        [value.first, value.last].any? { |bound| bound.is_a?(Float) }
      end

      def has_default?(column)
        return false unless column

        !column.default.nil?
      end

      def virtual?(column)
        column.nil?
      end

      def enum_attribute?
        # Check if it's an enum by looking at defined_enums
        if model_class.respond_to?(:defined_enums)
          model_class.defined_enums.key?(attr_name)
        elsif model_class.respond_to?(:pluralized_enum_values)
          # Rails 4 style
          pluralized_name = attr_name.pluralize
          model_class.pluralized_enum_values.key?(pluralized_name)
        else
          # Check for inclusion validator with string array
          validators_for(attr_name).any? do |v|
            v.instance_of?(ActiveModel::Validations::InclusionValidator) &&
              Array(v.options[:in]).all? { |val| val.is_a?(String) }
          end
        end
      end

      def type_based_filler(column)
        return noop_filler unless column

        case column.type
        when :string
          string_filler
        when :integer, :bigint, :smallint
          integer_filler
        when :float, :decimal
          float_filler
        when :boolean
          boolean_filler
        when :date
          date_filler
        when :datetime, :timestamp, :time
          datetime_filler
        when :json, :jsonb, :text, :binary
          string_filler # Treat as string for simplicity
        else
          noop_filler
        end
      end

      def noop_filler
        @noop_filler ||= NoopFiller.new(model_class, attr_name)
      end

      def string_filler
        @string_filler ||= StringFiller.new(model_class, attr_name)
      end

      def integer_filler
        @integer_filler ||= IntegerFiller.new(model_class, attr_name)
      end

      def float_filler
        @float_filler ||= FloatFiller.new(model_class, attr_name)
      end

      def boolean_filler
        @boolean_filler ||= BooleanFiller.new(model_class, attr_name)
      end

      def date_filler
        @date_filler ||= DateFiller.new(model_class, attr_name)
      end

      def datetime_filler
        @datetime_filler ||= DateTimeFiller.new(model_class, attr_name)
      end

      def enum_filler
        @enum_filler ||= EnumFiller.new(model_class, attr_name)
      end

      def acceptance_filler
        @acceptance_filler ||= AcceptanceFiller.new(model_class, attr_name)
      end

      def confirmation_filler
        @confirmation_filler ||= ConfirmationFiller.new(model_class, attr_name)
      end
    end
  end
end
