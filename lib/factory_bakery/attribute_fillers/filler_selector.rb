# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    # Routing policy: picks which generator handles one (target class,
    # attribute) pair. The decision consumes only the normalized facts in a
    # ConstraintSet -- shape (column-backed or validator-covered), schema type,
    # defaults, enums, STI ownership, value-shaping rules and validator hints
    # -- so the policy itself knows nothing about any framework.
    class FillerSelector
      attr_reader :model_class, :attr_name

      # Column types the mapper normalizes to plain symbols that hold text a
      # database casts on write. The symbol is data from the mapper, so the
      # routing policy stays framework-free (see ADR-0001). Add a type here
      # (and a rule in PlausibleStrings::TYPE_RULES) for another text-castable
      # type rather than reading a framework class in the core.
      STRINGISH_TEXT_TYPES = %i[inet cidr tsvector].freeze
      private_constant :STRINGISH_TEXT_TYPES

      # Fillers capture their constraints at construction and are otherwise
      # stateless: every `call` samples a fresh value. A bake resolves the
      # same model/attribute pair many times (once to generate, again for
      # confirmations, and once per uniqueness regeneration), so the resolved
      # filler is kept on the model class, not in the per-bake builder.
      # Reloading a model drops its cache with it.
      def self.cached_for(model_class, attr_name)
        # An attribute whose rules depend on the bound record cannot reuse a
        # cached filler (which captured its rules at construction) across
        # bakes of the same class with different state.
        return new(model_class, attr_name).call if model_class.frozen? || record_dependent?(model_class, attr_name)

        cache = model_class.instance_variable_get(:@factory_bakery_fillers) ||
                model_class.instance_variable_set(:@factory_bakery_fillers, {})

        key = attr_name.to_s
        cached = cache[key]
        return cached if cached

        filler = new(model_class, key).call
        # ConfirmationFiller exposes a mutable source value. It is only used
        # for its class in the gem, but never share that state with callers.
        return filler if defined?(ConfirmationFiller) && filler.is_a?(ConfirmationFiller)

        cache[key] = filler
      end

      def self.record_dependent?(model_class, attr_name)
        BuildContext.current_record.is_a?(model_class) &&
          FactoryBakery::MapperRegistry.record_dependent?(model_class, attr_name)
      end
      private_class_method :record_dependent?

      def initialize(model_class, attr_name)
        @model_class = model_class
        @attr_name = attr_name.to_s
        @constraints = ConstraintSet.for(model_class, @attr_name)
      end

      def call
        # Priority 1: Confirmation attribute (e.g., password_confirmation)
        return confirmation_filler if confirmation_attribute?

        # Priority 2: Acceptance attribute
        return acceptance_filler if acceptance_attribute?

        # Priority 3: a writer with side effects (Mastodon's Remotable
        # `avatar_remote_url=` downloads the URL it is given) must never
        # receive a heuristic value, not even when filling optional attributes.
        return guarded_writer_filler if @constraints.guarded_writer

        # Priority 4: the STI discriminator is owned by the framework; never
        # overwrite what `new` assigned.
        return noop_filler if @constraints.sti_discriminator

        # Priority 5: targets without a schema are routed by the rules their
        # validators expose instead of by column type.
        return validator_routed_filler unless @constraints.column_backed_target

        column_routed_filler
      end

      private

      def confirmation_attribute?
        return false unless attr_name.end_with?('_confirmation')
        return true unless @constraints.column_backed

        source = attr_name.delete_suffix('_confirmation')
        ConstraintSet.for(model_class, source).confirmation_validated
      end

      def acceptance_attribute?
        attr_name.end_with?('_accepted') || @constraints.acceptance_validated
      end

      def column_routed_filler
        # Priority 6: a virtual attribute has no column type, so its validators
        # decide the generator (issue #57). A name without validators of its
        # own (a bare confirmation twin) still routes to the no-op.
        return validator_routed_filler if virtual?

        # Priority 7: a defaulted column keeps its default unless a
        # value-shaping validator needs a generated value. Leaving a defaulted
        # column alone preserves a blank default (e.g. "" or false) that fails
        # presence/format/length/etc. on every bake, so this escape hatch is
        # decided before type routing.
        return noop_filler if @constraints.has_default && !@constraints.value_shaping

        # Priority 8: enum attribute
        return enum_filler if @constraints.enum_attribute

        # Priority 9: an Array-valued text column (`serialize :tags, type:
        # Array`) reports type :text but holds an Array, so a scalar String
        # would raise SerializationTypeMismatch on assignment. json/jsonb
        # columns are excluded: the JsonFiller decides their own shape.
        return array_filler if array_valued_text?

        type_based_filler
      end

      # Route a schema-less target by the rules its validators declare. The
      # attribute universe is already limited to validator-covered names by
      # the builder, so no-information attributes never reach this path.
      def validator_routed_filler
        return noop_filler unless @constraints.has_validators

        return inclusion_based_filler if @constraints.inclusion_validated

        return string_filler if @constraints.length_validated
        return string_filler if @constraints.format_validated

        return numericality_filler if @constraints.numericality_validated

        # Presence, exclusion and other validators carry no value of their
        # own; a name-derived string is still a valid generated default.
        string_filler
      end

      def inclusion_based_filler
        # The first inclusion validator's raw set decides the generator: the
        # mapper captured it separately because the generators themselves see
        # the last-set form.
        values = Array(@constraints.first_inclusion_values)
        return noop_filler if values.empty?
        return integer_filler if values.all? { |value| value.is_a?(Integer) }
        return float_filler if values.all? { |value| value.is_a?(Numeric) }

        string_filler
      end

      def numericality_filler
        return integer_filler if @constraints.numericality_only_integer

        @constraints.numericality_has_float_bound ? float_filler : integer_filler
      end

      # An attribute without a column is virtual: it has no schema type, so
      # its validators decide the generator.
      def virtual?
        !@constraints.column_backed
      end

      # JSON-backed column types: the JsonFiller decides their shape (Hash or
      # Array) from the normalized json_shape fact. Every other array-shaped
      # attribute is a text column serialized with an Array coder, which needs
      # the Array generator rather than a scalar String.
      JSON_COLUMN_TYPES = %i[json jsonb].freeze
      private_constant :JSON_COLUMN_TYPES

      def type_based_filler
        case @constraints.type
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
        when :json, :jsonb
          json_filler
        when :array
          array_filler
        when :text, :binary, *STRINGISH_TEXT_TYPES
          string_filler
        else
          noop_filler
        end
      end

      # A `serialize :tags, type: Array` text column reports type :text but its
      # normalized json shape is :array, so it needs the Array generator rather
      # than a scalar String.
      def array_valued_text?
        @constraints.json_shape == :array && !JSON_COLUMN_TYPES.include?(@constraints.type)
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

      def json_filler
        @json_filler ||= JsonFiller.new(model_class, attr_name)
      end

      def array_filler
        @array_filler ||= ArrayFiller.new(model_class, attr_name)
      end

      def acceptance_filler
        @acceptance_filler ||= AcceptanceFiller.new(model_class, attr_name)
      end

      # A guarded writer is left completely alone whenever the attribute can
      # stay blank: a virtual attribute, a nullable column and a defaulted
      # column all keep what `new` produced, so no setter runs and a column
      # default survives. Only a NOT NULL column without a default needs the
      # filler's empty String.
      def guarded_writer_filler
        return noop_filler if leavable_blank?

        @guarded_writer_filler ||= GuardedWriterFiller.new(model_class, attr_name)
      end

      def leavable_blank?
        !@constraints.column_backed || @constraints.nullable || @constraints.has_default
      end

      def confirmation_filler
        @confirmation_filler ||= ConfirmationFiller.new(model_class, attr_name)
      end
    end
  end
end
