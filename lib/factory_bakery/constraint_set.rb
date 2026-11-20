# frozen_string_literal: true

module FactoryBakery
  # The normalized, framework-agnostic description of everything the value
  # generators may know about one (target class, attribute) pair.
  #
  # A mapper plugin (the default one understands schema-backed models and
  # validator-bearing POROs) reads a real class and produces one of these.
  # Fillers and the routing policy consume it and never touch the source
  # framework: schema facts arrive as plain values (type, limits, nullability,
  # defaults), validation rules arrive as raw option forms (literals, Procs and
  # Symbols stay unresolved so bake-time lazy resolution keeps working), and
  # routing-only facts (value-shaping, enum presence, PORO routing hints)
  # arrive as booleans.
  #
  # Raw option forms are kept deliberately: a Proc or Symbol option is data
  # resolved against the object being built when a value is generated, fresh
  # for every bake (see AttributeFillers::ValueResolution).
  class ConstraintSet
    # Comparison/numericality bound options, shared by the two bound views.
    #   * numeric_bounds folds Numericality and Comparison validators (both
    #     write the same fields; odd/even/in come from numericality only);
    #     integer and float generators consume it.
    #   * comparison_bounds folds Comparison validators alone; date and
    #     datetime generators consume it. Keeping the views separate
    #     preserves the original per-filler validator matching exactly.
    Bounds = Struct.new(
      :greater_than, :greater_than_or_equal_to, :equal_to,
      :less_than, :less_than_or_equal_to, :other_than,
      :odd, :even, :in_range,
      keyword_init: true
    ) do
      def self.none
        new
      end
    end

    attr_reader :model_class, :attr_name,
                # Schema facts (nil when the attribute has no column).
                # :array is a normalized type for adapter-native array columns;
                # array_element_type is a plain-symbol hint (:string, :integer,
                # :float, :boolean) derived by the mapper plugin from the
                # column's underlying element type.
                :type, :array_element_type, :db_limit, :nullable, :has_default, :default_value, :precision, :scale,
                # Target/attribute shape flags.
                :column_backed, :column_backed_target, :sti_discriminator,
                # Shape of a JSON-backed attribute: :array when the attribute
                # is expected to hold an Array (an Array column default, a
                # serialized Array coder, an Array inclusion set), :hash
                # otherwise. The mapper plugin derives it; the core only sees
                # the symbol.
                :json_shape,
                # Length rules.
                :min_length, :max_length, :exact_length,
                # Format rules.
                :with_regexes, :without_regexes,
                # Set rules in raw option form (Array/Range/Proc/Symbol).
                :allowed_values, :forbidden_values,
                # Nullability rules.
                :must_be_present, :absence_required, :nil_rejected,
                # Acceptance rule.
                :accept_value,
                # Enum rules.
                :enum_attribute, :enum_values,
                # Routing facts.
                :has_validators, :value_shaping, :acceptance_validated, :confirmation_validated,
                :inclusion_validated, :first_inclusion_values,
                :length_validated, :format_validated,
                :numericality_validated, :numericality_only_integer,
                :numericality_has_float_bound,
                # True when the attribute's writer has side effects (a
                # remote-URL downloader), so heuristics must leave it blank.
                :guarded_writer,
                # Bound views.
                :numeric_bounds, :comparison_bounds

    def initialize(
      model_class:, attr_name:,
      type: nil, array_element_type: nil, db_limit: nil, nullable: nil, has_default: false, default_value: nil,
      precision: nil, scale: nil,
      column_backed: false, column_backed_target: false, sti_discriminator: false,
      json_shape: :hash,
      min_length: nil, max_length: nil, exact_length: nil,
      with_regexes: [].freeze, without_regexes: [].freeze,
      allowed_values: nil, forbidden_values: nil,
      must_be_present: false, absence_required: false, nil_rejected: false,
      accept_value: nil,
      enum_attribute: false, enum_values: [].freeze,
      has_validators: false, value_shaping: false, acceptance_validated: false,
      confirmation_validated: false,
      inclusion_validated: false, first_inclusion_values: nil,
      length_validated: false, format_validated: false,
      numericality_validated: false, numericality_only_integer: false,
      numericality_has_float_bound: false,
      guarded_writer: false,
      numeric_bounds: Bounds.none, comparison_bounds: Bounds.none
    )
      @model_class = model_class
      @attr_name = attr_name
      @type = type
      @array_element_type = array_element_type
      @db_limit = db_limit
      @nullable = nullable
      @has_default = has_default
      @default_value = default_value
      @precision = precision
      @scale = scale
      @column_backed = column_backed
      @column_backed_target = column_backed_target
      @sti_discriminator = sti_discriminator
      @json_shape = json_shape
      @min_length = min_length
      @max_length = max_length
      @exact_length = exact_length
      @with_regexes = with_regexes
      @without_regexes = without_regexes
      @allowed_values = allowed_values
      @forbidden_values = forbidden_values
      @must_be_present = must_be_present
      @absence_required = absence_required
      @nil_rejected = nil_rejected
      @accept_value = accept_value
      @enum_attribute = enum_attribute
      @enum_values = enum_values
      @has_validators = has_validators
      @value_shaping = value_shaping
      @acceptance_validated = acceptance_validated
      @confirmation_validated = confirmation_validated
      @inclusion_validated = inclusion_validated
      @first_inclusion_values = first_inclusion_values
      @length_validated = length_validated
      @format_validated = format_validated
      @numericality_validated = numericality_validated
      @numericality_only_integer = numericality_only_integer
      @numericality_has_float_bound = numericality_has_float_bound
      @guarded_writer = guarded_writer
      @numeric_bounds = numeric_bounds
      @comparison_bounds = comparison_bounds
    end

    # The one seam through which a generator obtains its constraints: the
    # target class and attribute name are resolved into a normalized set by
    # whichever mapper plugin understands the class. Targets no mapper can
    # introspect get the all-defaults set, which routes to a no-op exactly as
    # duck-typed lookups did before mappers existed.
    def self.for(model_class, attr_name)
      FactoryBakery::MapperRegistry.constraints_for(model_class, attr_name)
    end

    # The all-defaults set for targets no mapper can introspect.
    def self.empty(model_class, attr_name)
      new(model_class: model_class, attr_name: attr_name.to_s)
    end
  end
end
