# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    class StringFiller
      include CommonValidators

      # Bounded regeneration for format/exclusion constraints, matching the
      # uniqueness enforcer's budget. Exhaustion raises a contextual error
      # instead of returning a value that fails validation.
      MAX_ATTEMPTS = 10

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
        @with_regexes = []
        @without_regexes = []
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

        # 3. Generate and verify a value that satisfies every constraint
        generate_compliant_value(context)
      end

      def apply_validator(validator)
        return true if apply_common_validator(validator)

        case validator.class.name
        when 'ActiveModel::Validations::LengthValidator', 'ActiveRecord::Validations::LengthValidator'
          apply_length_validator(validator.options)
        when 'ActiveModel::Validations::FormatValidator'
          # Rails forbids both keys in a single declaration, but an attribute
          # can carry several FormatValidators. Keep every regex so verification
          # covers the full set instead of the last one declared.
          @with_regexes << validator.options[:with] if validator.options[:with]
          @without_regexes << validator.options[:without] if validator.options[:without]
          true
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

      # Generate up to MAX_ATTEMPTS candidates and return the first one that
      # satisfies every constraint. A candidate is never returned unverified:
      # exhaustion raises instead of leaking a value Rails would reject.
      def generate_compliant_value(context)
        value = nil
        attempts = 0
        loop do
          value = build_candidate
          return value if compliant?(value, context)

          attempts += 1
          raise format_exhaustion_error(value) if attempts >= MAX_ATTEMPTS
        end
      end

      def build_candidate
        value = generate_value
        # Truncating/padding a regex-generated value is what turns a compliant
        # value into a non-match. For regex-constrained strings, length is a
        # verification predicate instead of a post-processing step.
        return value if @with_regexes.any?

        adjust_length(value)
      end

      def compliant?(value, context)
        return false if value.nil?
        return false unless matches_with_regexes?(value)
        return false if matches_without_regexes?(value)
        return false if forbidden_values?(value, context)

        length_compliant?(value)
      end

      def matches_with_regexes?(value)
        @with_regexes.all? { |regex| regex.match?(value) }
      end

      def matches_without_regexes?(value)
        @without_regexes.any? { |regex| regex.match?(value) }
      end

      def length_compliant?(value)
        length_constraints.all? { |kind, bound| length_satisfies?(value.length, kind, bound) }
      end

      def length_satisfies?(length, kind, bound)
        case kind
        when :is then length == bound
        when :minimum then length >= bound
        else length <= bound
        end
      end

      def length_constraints
        { is: @exact_length, minimum: @min_length, maximum: @max_length, db_limit: @db_limit }.compact
      end

      def generate_value
        # Priority 1: Format regex constraint
        return generate_from_regex if @with_regexes.any?

        # Priority 2: Attribute name patterns
        generate_by_pattern
      end

      def generate_from_regex
        # FFaker cannot express every regex. Its fallback may violate the
        # pattern, so the result is verified by generate_compliant_value.
        return generate_by_pattern unless FFaker::String.respond_to?(:from_regexp)

        FFaker::String.from_regexp(@with_regexes.first)
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

      def format_exhaustion_error(value)
        name = "#{@model_class}##{@attr_name}"

        FactoryBakery::Error.new(
          "could not generate a format-compliant value for #{name} " \
          "(#{format_constraints_description}): #{value.inspect} failed after " \
          "#{MAX_ATTEMPTS} attempts. Pass an explicit value with an override " \
          'or relax the constraints.'
        )
      end

      def format_constraints_description
        parts = []
        parts << "with: #{@with_regexes.map(&:inspect).join(', ')}" if @with_regexes.any?
        parts << "without: #{@without_regexes.map(&:inspect).join(', ')}" if @without_regexes.any?
        parts << "length constraints: #{length_constraints.inspect}" unless length_constraints.empty?
        parts.join('; ')
      end
    end
  end
end
