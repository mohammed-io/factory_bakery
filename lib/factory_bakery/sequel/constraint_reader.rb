# frozen_string_literal: true

module FactoryBakery
  module Sequel
    # The single place that reads one Sequel::Model class and normalizes
    # everything the generators need into a ConstraintSet. Schema facts come
    # from db_schema; stored validation rules come from
    # validation_class_methods' reflective declarations. The generators and
    # the routing policy consume the normalized result and never read the
    # source framework themselves.
    #
    # Stored reflections are folded in declaration order exactly like the
    # default mapper folds its validator objects: each reflection type
    # writes only the fields it owns, so re-declaring the same type resolves
    # last-wins.
    class ConstraintReader
      # Sequel schema type symbols translated into the core type vocabulary
      # the routing policy understands (its fillers route on these symbols).
      # An unmapped type stays nil, which routes to the no-op filler rather
      # than guessing at an unknown column shape.
      TYPE_MAP = {
        integer: :integer, bigint: :integer, smallint: :integer,
        string: :string, text: :text, blob: :binary,
        float: :float, decimal: :decimal, numeric: :decimal,
        date: :date, datetime: :datetime, timestamp: :datetime, time: :time,
        boolean: :boolean, json: :json, jsonb: :jsonb
      }.freeze

      # Reflection types that force a generated value even on a defaulted
      # column (mirroring the default mapper's value-shaping set): keeping a
      # blank default would fail the reflection on every bake.
      VALUE_SHAPING_TYPES = %i[presence length format inclusion numericality uniqueness].freeze

      # Reflections whose absence of allow_nil/allow_blank means a nil value
      # cannot satisfy them (length only with a positive minimum).
      NIL_REJECTING_TYPES = %i[presence inclusion format numericality acceptance].freeze

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
        column = @model_class.db_schema[@attr_name.to_sym]
        reflections = stored_reflections(@attr_name)

        rules = fold_reflections(reflections)
        array_column = array_column?(column)

        ConstraintSet.new(
          model_class: @model_class,
          attr_name: @attr_name,
          type: array_column ? :array : translated_type(column),
          array_element_type: array_column ? translated_array_element_type(column) : nil,
          db_limit: column&.fetch(:max_length, nil),
          nullable: column&.fetch(:allow_null, nil),
          has_default: !column.nil? && !column[:default].nil?,
          default_value: column&.fetch(:default, nil),
          precision: precision_of(column),
          scale: scale_of(column),
          column_backed: !column.nil?,
          column_backed_target: true,
          min_length: rules.min_length,
          max_length: rules.max_length,
          exact_length: rules.exact_length,
          with_regexes: rules.with_regexes.freeze,
          without_regexes: rules.without_regexes.freeze,
          allowed_values: rules.allowed_values,
          forbidden_values: rules.forbidden_values,
          must_be_present: rules.must_be_present,
          absence_required: rules.absence_required,
          nil_rejected: nil_rejecting?(reflections),
          accept_value: rules.accept_value,
          has_validators: !reflections.empty?,
          value_shaping: reflections.any? { |type, _opts| VALUE_SHAPING_TYPES.include?(type) },
          acceptance_validated: rules.acceptance_validated,
          inclusion_validated: rules.inclusion_validated,
          first_inclusion_values: rules.first_inclusion_values,
          length_validated: rules.length_validated,
          format_validated: rules.format_validated,
          numericality_validated: rules.numericality_validated,
          numericality_only_integer: rules.numericality_only_integer,
          numeric_bounds: rules.numeric_bounds,
          comparison_bounds: rules.comparison_bounds
        )
      end

      # Human-readable reflection descriptions for exhaustion errors.
      def self.describe_reflection(type, opts)
        ignored = %i[message tag nil_message too_long too_short wrong_length]
        meaningful = opts.reject { |key, _| ignored.include?(key) }
        meaningful.empty? ? type.to_s : "#{type}: #{meaningful.inspect}"
      end

      private

      # A small mutable accumulator folded over the attribute's stored
      # reflections in declaration order, mirroring the default mapper's
      # validator fold.
      Rules = Struct.new(
        :min_length, :max_length, :exact_length,
        :with_regexes, :without_regexes,
        :allowed_values, :forbidden_values,
        :must_be_present, :absence_required, :accept_value,
        :acceptance_validated, :inclusion_validated, :first_inclusion_values,
        :length_validated, :format_validated,
        :numericality_validated, :numericality_only_integer,
        :numeric_bounds, :comparison_bounds,
        keyword_init: true
      ) do
        def self.none
          new(
            with_regexes: [], without_regexes: [],
            must_be_present: false, absence_required: false,
            inclusion_validated: false, length_validated: false, format_validated: false,
            numericality_validated: false, numericality_only_integer: false,
            numeric_bounds: ConstraintSet::Bounds.new, comparison_bounds: ConstraintSet::Bounds.new
          )
        end
      end
      private_constant :Rules

      def fold_reflections(reflections)
        reflections.each_with_object(Rules.none) do |(type, opts), rules|
          case type
          when :presence
            rules.must_be_present = true
          when :length
            rules.length_validated = true
            apply_length_reflection(rules, opts)
          when :numericality
            rules.numericality_validated = true
            rules.numericality_only_integer = opts[:only_integer] ? true : false
          when :format
            rules.format_validated = true
            # An attribute can carry several format reflections: keep every
            # regex so verification covers the full set.
            rules.with_regexes << opts[:with] if opts[:with]
            rules.without_regexes << opts[:without] if opts[:without]
          when :inclusion
            # Keep the raw Sequel option form; a Proc set is resolved at
            # value-generation time, exactly as for the default mapper.
            rules.allowed_values = opts[:in]
            unless rules.inclusion_validated
              rules.inclusion_validated = true
              rules.first_inclusion_values = opts[:in]
            end
          when :exclusion
            rules.forbidden_values = opts[:in]
          when :acceptance
            rules.acceptance_validated = true
            rules.accept_value = opts[:accept]
          end
        end
      end

      def nil_rejecting?(reflections)
        reflections.any? { |type, opts| nil_rejecting_reflection?(type, opts) }
      end

      def nil_rejecting_reflection?(type, opts)
        return false unless NIL_REJECTING_TYPES.include?(type) || type == :length
        return false if opts[:allow_nil] || opts[:allow_blank]

        return positive_length?(minimum_of(opts)) if type == :length

        true
      end

      def minimum_of(opts)
        opts[:minimum] || opts[:is] || opts[:within]&.first
      end

      def positive_length?(minimum)
        return true if minimum.is_a?(Proc) || minimum.is_a?(Symbol)

        minimum.to_i.positive?
      end

      def apply_length_reflection(rules, opts)
        rules.min_length = opts[:minimum]
        rules.max_length = opts[:maximum]
        rules.exact_length = opts[:is]
        rules.min_length ||= opts[:within]&.first
        rules.max_length ||= opts[:within]&.last
      end

      # Sequel's schema hash keeps the raw db_type string; numeric precision
      # and scale live there ("numeric(10, 2)") rather than in typed fields.
      def precision_of(column)
        match = column&.fetch(:db_type, nil)&.match(/\(\s*(\d+)\s*,\s*\d+\s*\)/)
        match && match[1].to_i
      end

      def scale_of(column)
        match = column&.fetch(:db_type, nil)&.match(/\(\s*\d+\s*,\s*(\d+)\s*\)/)
        match && match[1].to_i
      end

      # Some adapters report json-ish columns with a nil schema type and a
      # "json" db_type (SQLite's JSON1 columns); recognized adapters report
      # :json / :jsonb directly.
      def translated_type(column)
        return nil if column.nil?

        type = column[:type]
        return :json if type.nil? && column[:db_type].to_s.include?('json')

        TYPE_MAP.fetch(type, nil)
      end

      # Sequel's PostgreSQL adapter reports array columns with schema type
      # :array, and some versions only expose a "[]"-suffixed db_type. Best
      # effort: recognize both and derive the element hint from db_type. An
      # adapter that reports something else keeps its native type, so array
      # routing is never attempted there.
      def array_column?(column)
        return false if column.nil?

        column[:type] == :array || column[:db_type].to_s.end_with?('[]')
      end

      def translated_array_element_type(column)
        base_type = column[:db_type].to_s.sub(/\[\]\z/, '').downcase
        case base_type
        when /int/ then :integer
        when /float|double|decimal|numeric|real/ then :float
        when /bool/ then :boolean
        else :string
        end
      end

      # Stored validations, or nothing when the class does not use the
      # reflective declaration API. Array keys are grouped validations
      # (composite uniqueness) and never match a single attribute.
      def stored_reflections(attr_name)
        return [] unless @model_class.respond_to?(:validation_reflections)

        Array(@model_class.validation_reflections[attr_name.to_sym])
      end
    end
  end
end
