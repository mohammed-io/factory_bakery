# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    class StringFiller
      include CommonValidators

      def initialize(model_class, attr_name)
        @model_class = model_class
        @attr_name = attr_name.to_s

        # Schema constraints from columns_hash
        @column = column_for(model_class, attr_name)
        @db_limit = @column&.limit
        @nullable = @column&.null
        @has_default = @column&.default

        # Validation constraints (accumulated from validators)
        @min_length = nil
        @max_length = nil
        @exact_length = nil
        @format_regex = nil
        @allowed_values = nil
        @forbidden_values = nil
        @must_be_present = false
        @absence_required = false

        # Process all validators for this attribute
        validators_for(model_class, attr_name).each do |validator|
          apply_validator(validator)
        end
      end

      def call(context = nil)
        # 1. Absence validator takes precedence
        return nil if absence_required?

        # 2. Inclusion validator - pick from allowed set
        return pick_from_allowed(context) if allowed_values?

        # 3. Generate value respecting constraints
        value = generate_value

        # 4. Adjust to length constraints
        value = adjust_length(value)

        # 5. Ensure not in exclusion set
        avoid_forbidden(value, context)
      end

      def apply_validator(validator)
        return true if apply_common_validator(validator)

        case validator.class.name
        when 'ActiveModel::Validations::LengthValidator', 'ActiveRecord::Validations::LengthValidator'
          apply_length_validator(validator.options)
        when 'ActiveModel::Validations::FormatValidator'
          @format_regex = validator.options[:with]
        else
          false
        end
      end

      private

      def apply_length_validator(opts)
        @min_length = opts[:minimum]
        @max_length = opts[:maximum]
        @exact_length = opts[:is]
        @min_length ||= opts[:in]&.first
        @max_length ||= opts[:in]&.last
      end

      def pick_from_allowed(context)
        value = pick_from(@allowed_values, context)
        value.to_s
      end

      def generate_value
        # Priority 1: Format regex constraint
        return generate_from_regex if @format_regex

        # Priority 2: Attribute name patterns
        generate_by_pattern
      end

      def generate_from_regex
        # Try to use FFaker's from_regexp if available
        if FFaker::String.respond_to?(:from_regexp)
          FFaker::String.from_regexp(@format_regex)
        else
          # Fallback: generate a random string
          generate_by_pattern
        end
      rescue StandardError
        generate_by_pattern
      end

      def generate_by_pattern
        case @attr_name
        when /email/
          FFaker::Internet.email
        when /phone/
          FFaker::PhoneNumber.phone_number
        when /name/
          FFaker::Name.name
        when /address|street|city/
          FFaker::Address.street_address
        when /url|website|link/
          FFaker::Internet.http_url
        when /username/
          FFaker::Internet.user_name
        when /title/
          FFaker::Lorem.word.capitalize
        when /body|description|content/
          FFaker::Lorem.sentence
        when /priority/
          rand(1..5).to_s
        else
          FFaker::Lorem.word
        end
      end

      def adjust_length(value)
        return value if value.nil?

        # Exact length takes priority
        if @exact_length
          return set_to_length(value, @exact_length)
        end

        # Apply max constraint
        if @max_length && value.length > @max_length
          value = truncate_to_length(value, @max_length)
        end

        # Apply min constraint
        if @min_length && value.length < @min_length
          value = pad_to_length(value, @min_length)
        end

        # Apply database limit
        if @db_limit && value.length > @db_limit
          value = truncate_to_length(value, @db_limit)
        end

        value
      end

      def set_to_length(value, target_length)
        if value.length == target_length
          value
        elsif value.length > target_length
          truncate_to_length(value, target_length)
        else
          pad_to_length(value, target_length)
        end
      end

      def truncate_to_length(value, max_length)
        value[0, max_length]
      end

      def pad_to_length(value, min_length)
        return value if value.length >= min_length

        padding_needed = min_length - value.length
        padding = generate_padding(padding_needed)
        value + padding
      end

      def generate_padding(length)
        # Generate random padding characters
        chars = ('a'..'z').to_a + ('0'..'9').to_a
        padding = ''
        length.times { padding += chars.sample }
        padding
      end

      def avoid_forbidden(value, context = nil)
        return value unless @forbidden_values

        attempts = 0
        while forbidden_values?(value, context) && attempts < 10
          value = generate_value
          value = adjust_length(value)
          attempts += 1
        end
        value
      end
    end
  end
end
