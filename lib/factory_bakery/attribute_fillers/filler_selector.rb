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

        # Get column info for type-based routing
        column = model_class.columns_hash[attr_name]

        # Priority 3: Has default or virtual attribute -> Noop
        return noop_filler if has_default?(column) || virtual?(column)

        # Priority 4: Enum attribute
        return enum_filler if enum_attribute?

        # Priority 5: Type-based routing
        type_based_filler(column)
      end

      private

      def confirmation_attribute?
        attr_name.end_with?('_confirmation')
      end

      def acceptance_attribute?
        attr_name.end_with?('_accepted') ||
          model_class.validators_on(attr_name).any? do |v|
            v.instance_of?(ActiveModel::Validations::AcceptanceValidator)
          end
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
          model_class.validators_on(attr_name).any? do |v|
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
