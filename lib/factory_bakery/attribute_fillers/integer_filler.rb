# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    class IntegerFiller
      include ValueResolution
      include NumericConstraintHygiene

      # A pure generator: the constraints arrive already normalized in a
      # ConstraintSet, resolved from the target once at construction.
      def initialize(model_class, attr_name)
        @model_class = model_class
        @attr_name = attr_name.to_s
        @constraints = ConstraintSet.for(model_class, @attr_name)

        # Numericality/comparison constraints (raw option forms, resolved at
        # bake time against the object being built)
        bounds = @constraints.numeric_bounds
        @greater_than = bounds.greater_than
        @greater_than_or_equal_to = bounds.greater_than_or_equal_to
        @equal_to = bounds.equal_to
        @less_than = bounds.less_than
        @less_than_or_equal_to = bounds.less_than_or_equal_to
        @other_than = bounds.other_than
        @odd_only = bounds.odd
        @even_only = bounds.even
        @in_range = bounds.in_range
      end

      def call(context = nil)
        # 1. Absence validator takes precedence
        return nil if absence_required?

        # 2. Inclusion validator - pick from allowed set
        return pick_from_allowed(context) if allowed_values?

        # 3. Generate a value checked against every post-generation constraint
        generate_numeric_value(context) { generate_value(context) }
      end

      private

      def pick_from_allowed(context)
        pick_from(@constraints.allowed_values, context).to_i
      end

      def generate_value(context)
        # Priority 1: Equal to constraint
        equal_to = resolve_option_value(@equal_to, context)
        return equal_to.to_i if equal_to

        # Priority 2: Range constraint
        in_range = resolve_range(resolve_option_value(@in_range, context), context)
        return generate_in_range(in_range) if in_range

        # Priority 3: Comparison constraints
        lower_bound = calculate_lower_bound(context)
        upper_bound = calculate_upper_bound(context)

        # Priority 4: Attribute name patterns
        return generate_by_pattern if lower_bound.nil? && upper_bound.nil?

        # Generate within bounds. Only explicitly supplied sides are hard
        # limits for the parity fix-up; defaulted sides may be widened by one
        # when the required parity cannot otherwise be reached.
        generate_in_bounds(lower_bound, upper_bound,
                           lower_explicit: !lower_bound.nil?,
                           upper_explicit: !upper_bound.nil?,
                           context: context)
      end

      def calculate_lower_bound(context)
        greater_than_or_equal_to = resolve_option_value(@greater_than_or_equal_to, context)
        return greater_than_or_equal_to.to_i if greater_than_or_equal_to

        greater_than = resolve_option_value(@greater_than, context)
        return greater_than.to_i + 1 if greater_than

        nil
      end

      def calculate_upper_bound(context)
        less_than_or_equal_to = resolve_option_value(@less_than_or_equal_to, context)
        return less_than_or_equal_to.to_i if less_than_or_equal_to

        less_than = resolve_option_value(@less_than, context)
        return less_than.to_i - 1 if less_than

        nil
      end

      def generate_in_range(range)
        values = range.to_a
        return nil if values.empty?

        value = values.sample.to_i
        apply_odd_even_constraint(value, values.first.to_i, values.last.to_i,
                                  lower_explicit: true, upper_explicit: true)
      end

      def generate_in_bounds(lower, upper, lower_explicit: false, upper_explicit: false, context: nil)
        lower_was_nil = lower.nil?
        upper_was_nil = upper.nil?
        lower ||= 0
        upper ||= 100

        if lower > upper
          # Extend a default side when only one bound was supplied; swapping
          # would put the generated value outside the supplied constraint.
          if lower_was_nil
            lower = upper
          elsif upper_was_nil
            upper = lower
          else
            lower, upper = upper, lower
          end
        end

        # Small explicit windows are enumerated, not guessed: other_than,
        # exclusions and parity are filters over the candidates, which removes
        # the retry-budget flake when the valid space is tiny (e.g. 4..5 with
        # other_than: 5 leaving exactly one survivor).
        if lower_explicit && upper_explicit && (upper - lower) <= 64
          candidates = (lower..upper).to_a
          forbidden = context ? resolve_other_than(context) : nil
          candidates.delete_if { |v| forbidden && v == forbidden } if forbidden
          candidates.reject! { |v| @constraints.forbidden_values&.include?(v) } if @constraints.forbidden_values
          candidates.select!(&:odd?) if @odd_only
          candidates.select!(&:even?) if @even_only
          return candidates.sample unless candidates.empty?
        end

        value = rand(lower..upper)
        apply_odd_even_constraint(value, lower, upper,
                                  lower_explicit: lower_explicit && !lower_was_nil,
                                  upper_explicit: upper_explicit && !upper_was_nil)
      end

      def generate_by_pattern
        case @attr_name
        when /age|priority/
          generate_in_bounds(18, 65)
        when /score|rating|percentage/
          generate_in_bounds(0, 100)
        when /quantity/
          generate_in_bounds(1, 100)
        when /price/
          generate_in_bounds(1, 1000)
        when /number/
          generate_in_bounds(1, 999)
        else
          generate_in_bounds(1, 100)
        end
      end

      # Parity is reached by moving to an adjacent value that still fits the
      # constraint window, never by stepping past an explicit bound (the old
      # `value + 1` bug turned `even: true, <= 7` into 8). When no adjacent
      # value fits, only a non-explicit side may be widened by one.
      def apply_odd_even_constraint(value, lower = nil, upper = nil,
                                    lower_explicit: false, upper_explicit: false)
        return value unless @odd_only || @even_only
        return value if parity_matches?(value)

        candidates = [value + 1, value - 1].select { |candidate| parity_matches?(candidate) }

        inside = candidates.select { |candidate| within_numeric_bounds?(candidate, lower, upper) }
        return inside.first unless inside.empty?

        candidates.each do |candidate|
          next if lower_explicit && lower && candidate < lower
          next if upper_explicit && upper && candidate > upper

          return candidate
        end

        raise numeric_constraint_error(value, "parity within #{lower.inspect}..#{upper.inspect}")
      end

      def parity_matches?(value)
        @odd_only ? value.odd? : value.even?
      end

      def within_numeric_bounds?(value, lower, upper)
        return false if lower && value < lower
        return false if upper && value > upper

        true
      end

      def resolve_other_than(context)
        resolved = resolve_option_value(@other_than, context)
        resolved.nil? ? nil : resolved.to_i
      end

      # The numeric view of `other_than` (numericality and comparison
      # validators both write it).
      def other_than_option
        @other_than
      end
    end
  end
end
