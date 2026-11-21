# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    class IntegerFiller
      include ValueResolution
      include NumericConstraintHygiene

      SMALL_RANGE_WINDOW = 64

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
        values = @constraints.allowed_values
        if values.is_a?(Range) && (bounds = range_bounds(values, context))
          value = generate_in_range(*bounds, context)
          return value.to_i if value
        end

        pick_from(values, context).to_i
      end

      def generate_value(context)
        # Priority 1: Equal to constraint
        equal_to = resolve_option_value(@equal_to, context)
        return equal_to.to_i if equal_to

        # Priority 2: Range constraint. One open side is allowed; a range with
        # both sides open carries no information and falls through to bounds.
        bounds = resolved_range_bounds(context)
        return generate_in_range(*bounds, context) if bounds

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

      # Bounds come from the range endpoints, never from materializing it: a
      # numericality range such as -(2**31)..(2**31) would otherwise allocate
      # billions of integers. Float endpoints are rounded inward so the sampled
      # integer is covered by the original range.
      def generate_in_range(first, last, exclude_end, context = nil)
        lower_bound = integer_range_bound(first, :lower)
        direction = exclude_end ? :upper_exclusive : :upper_inclusive
        upper_bound = integer_range_bound(last, direction)
        return nil if upper_bound && lower_bound && upper_bound < lower_bound

        sample_within_range(lower_bound, upper_bound, context)
      end

      def sample_within_range(lower_bound, upper_bound, context)
        lower, upper = range_window(lower_bound, upper_bound)
        return sample_small_window(lower, upper, context) if small_window?(lower_bound, upper_bound)

        value = Randomness.rand(lower..upper)
        apply_odd_even_constraint(value, lower, upper,
                                  lower_explicit: !lower_bound.nil?,
                                  upper_explicit: !upper_bound.nil?)
      end

      # An open side gets a bounded window next to the supplied side.
      def range_window(lower_bound, upper_bound)
        lower = lower_bound || (upper_bound ? upper_bound - SMALL_RANGE_WINDOW : 0)
        upper = upper_bound || (lower_bound ? lower_bound + SMALL_RANGE_WINDOW : SMALL_RANGE_WINDOW)
        [lower, upper]
      end

      def small_window?(lower_bound, upper_bound)
        lower_bound && upper_bound && (upper_bound - lower_bound) <= SMALL_RANGE_WINDOW
      end

      # Small explicit windows are filtered instead of guessed: the single
      # survivor of `4..5, other_than: 5` is found without retry flake.
      def sample_small_window(lower, upper, context)
        survivors = (lower..upper).select { |value| parity_matches?(value) && numeric_compliant?(value, context) }
        Randomness.sample(survivors) unless survivors.empty?
      end

      def resolved_range_bounds(context)
        range = resolve_option_value(@in_range, context)
        range_bounds(range, context) if range.is_a?(Range)
      end

      # Endpoints may be Procs or Symbols resolved against the object being
      # built. A beginless or endless range leaves one side nil.
      def range_bounds(range, context)
        first = resolve_option_value(range.begin, context)
        last = resolve_option_value(range.end, context)
        return nil if first.nil? && last.nil?

        [first, last, range.exclude_end?]
      end

      # An infinite endpoint carries no bound, exactly like a nil one.
      def integer_range_bound(value, direction)
        return nil if value.nil? || (value.is_a?(Float) && value.infinite?)
        return rounded_integer(value, :ceil) if direction == :lower
        return rounded_integer(value, :floor) if direction == :upper_inclusive

        rounded_integer(value, :ceil) - 1
      end

      def rounded_integer(value, rounding)
        return value.to_i unless value.is_a?(Float)

        rounding == :ceil ? value.ceil : value.floor
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
        if lower_explicit && upper_explicit && (upper - lower) <= SMALL_RANGE_WINDOW
          candidates = (lower..upper).to_a
          forbidden = context ? resolve_other_than(context) : nil
          candidates.delete_if { |v| forbidden && v == forbidden } if forbidden
          candidates.reject! { |v| @constraints.forbidden_values&.include?(v) } if @constraints.forbidden_values
          candidates.select!(&:odd?) if @odd_only
          candidates.select!(&:even?) if @even_only
          return Randomness.sample(candidates) unless candidates.empty?
        end

        value = Randomness.rand(lower..upper)
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

      # No parity rule means every integer matches.
      def parity_matches?(value)
        return value.odd? if @odd_only
        return value.even? if @even_only

        true
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
