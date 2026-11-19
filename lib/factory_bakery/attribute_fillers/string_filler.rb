# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    class StringFiller
      include ValueResolution
      include PlausibleStrings

      # Bounded regeneration for format/exclusion constraints, matching the
      # uniqueness enforcer's budget. Exhaustion raises a contextual error
      # instead of returning a value that fails validation.
      MAX_ATTEMPTS = 10

      # Bake-time resolved length bounds. The raw options stay on the filler so
      # a Proc or Symbol is re-evaluated for every `call`, not frozen at setup.
      ResolvedLengths = Struct.new(:minimum, :maximum, :exact, keyword_init: true)
      private_constant :ResolvedLengths

      # Hard bounds around synthesis itself: the deadline caps total
      # generation work for one attribute (one filler invocation), and the
      # attempt cap bounds raw generator calls.
      SYNTHESIS_TIME_LIMIT = 2.0
      SYNTHESIS_ATTEMPT_CAP = 25

      # A pure generator: the constraints arrive already normalized in a
      # ConstraintSet, resolved from the target once at construction.
      def initialize(model_class, attr_name)
        @model_class = model_class
        @attr_name = attr_name.to_s
        @constraints = ConstraintSet.for(model_class, @attr_name)

        # Schema constraints
        @db_limit = @constraints.db_limit

        # Validation constraints (normalized from the target's validators).
        # Procs and Symbols stay raw here and are resolved at bake time.
        @min_length = @constraints.min_length
        @max_length = @constraints.max_length
        @exact_length = @constraints.exact_length
        @with_regexes = @constraints.with_regexes
        @without_regexes = @constraints.without_regexes
      end

      def call(context = nil)
        # 1. Absence validator takes precedence
        return nil if absence_required?

        # 2. Inclusion validator - pick from allowed set
        return pick_from_allowed(context) if allowed_values?

        # 3. Generate and verify a value that satisfies every constraint
        generate_compliant_value(context)
      end

      private

      def pick_from_allowed(context)
        value = pick_from(@constraints.allowed_values, context)
        value.to_s
      end

      # Generate up to MAX_ATTEMPTS candidates and return the first one that
      # satisfies every constraint. A candidate is never returned unverified:
      # exhaustion raises instead of leaking a value the target would reject.
      def generate_compliant_value(context)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + SYNTHESIS_TIME_LIMIT
        lengths = resolve_lengths(context)
        value = nil
        attempts = 0
        synthesis_attempts = 0
        loop do
          exhausted = attempts >= MAX_ATTEMPTS ||
                      synthesis_attempts >= SYNTHESIS_ATTEMPT_CAP ||
                      past_deadline?(deadline)
          raise format_exhaustion_error(value) if exhausted

          value = build_candidate(lengths, context)
          synthesis_attempts += 1
          return value if compliant?(value, context, lengths)

          attempts += 1
        end
      end

      # Resolve every dynamic length option once per bake. A Symbol bound asks
      # the context for the referenced attribute, which generates it on first
      # use (even when it comes later in column order) and caches the result,
      # so both attributes end up filled and the bound stays stable across
      # regeneration attempts. An unresolvable or non-finite bound is dropped,
      # matching comparison-option relaxation; anything unusable raises.
      def resolve_lengths(context)
        ResolvedLengths.new(
          minimum: resolve_length(@min_length, :minimum, context),
          maximum: resolve_length(@max_length, :maximum, context),
          exact: resolve_length(@exact_length, :is, context)
        )
      end

      def resolve_length(raw, kind, context)
        coerce_length(resolve_length_option(raw, context, kind), raw, kind)
      end

      def coerce_length(value, raw, kind)
        return nil if value.nil?
        return nil if value == Float::INFINITY || value == -Float::INFINITY

        integer = integer_length(value)
        return integer if integer && integer >= 0

        raise length_resolution_error(raw, value, kind)
      end

      def integer_length(value)
        Integer(value)
      rescue ArgumentError, TypeError, FloatDomainError
        nil
      end

      def length_resolution_error(raw, value, kind)
        FactoryBakery::Error.new(
          "#{@model_class}##{@attr_name}: length :#{kind} #{raw.inspect} resolved to " \
          "#{value.inspect}, which is not a usable length; pass an explicit value " \
          'with an override or use a non-negative Integer'
        )
      end

      def past_deadline?(deadline)
        Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      end

      def build_candidate(lengths, context)
        value = generate_value(lengths, context)
        # Truncating/padding a regex-generated value is what turns a compliant
        # value into a non-match. For regex-constrained strings, length is a
        # verification predicate instead of a post-processing step.
        return value if @with_regexes.any?

        adjust_length(value, lengths)
      end

      def compliant?(value, context, lengths)
        return false if value.nil?
        return false unless matches_with_regexes?(value)
        return false if matches_without_regexes?(value)
        return false if forbidden_values?(value, context)

        length_compliant?(value, lengths)
      end

      def matches_with_regexes?(value)
        @with_regexes.all? { |regex| regex.match?(value) }
      end

      def matches_without_regexes?(value)
        @without_regexes.any? { |regex| regex.match?(value) }
      end

      def length_compliant?(value, lengths)
        length_constraints(lengths).all? { |kind, bound| length_satisfies?(value.length, kind, bound) }
      end

      def length_satisfies?(length, kind, bound)
        case kind
        when :is then length == bound
        when :minimum then length >= bound
        else length <= bound
        end
      end

      def length_constraints(lengths)
        { is: lengths.exact, minimum: lengths.minimum, maximum: lengths.maximum, db_limit: @db_limit }.compact
      end

      # The raw option forms are the debugging surface: an exhaustion message
      # should name `:max_chars` or the Proc the caller wrote, not its resolved
      # value from this particular bake.
      def length_options
        { is: @exact_length, minimum: @min_length, maximum: @max_length, db_limit: @db_limit }.compact
      end

      def generate_value(lengths, context)
        # Priority 1: Format regex constraint. For a URL-named attribute a few
        # plausible, reserved-domain candidates are checked against every
        # declared constraint first; synthesis is the fallback when none fits.
        return generate_with_format(lengths, context) if @with_regexes.any?

        # Priority 2: Column type / attribute name patterns. The cap is passed
        # down so a name-like value keeps its entropy suffix when truncated.
        generate_by_pattern(max_length: pattern_max_length(lengths), type: @constraints.type)
      end

      # Verification is shared with the ordinary candidate loop: a URL
      # candidate is never returned unless it satisfies the format, length and
      # exclusion constraints too. Both the lookahead URI regex and
      # URI.regexp(%w[http https]) already synthesize valid values; the
      # candidate-first step just makes a URL-named attribute produce a
      # reserved URL instead of synthesized characters.
      def generate_with_format(lengths, context)
        candidate = plausible_url_candidates.find { |value| compliant?(value, context, lengths) }
        return candidate if candidate

        generate_from_regex(lengths)
      end

      # The same cap #adjust_length enforces, in the same precedence order.
      def pattern_max_length(lengths)
        [lengths.exact || lengths.maximum, @db_limit].compact.min
      end

      # The regex generator walks the regex itself, so an unsupported or
      # unsatisfiable regex yields no candidate at all: the verifier turns
      # that into the contextual exhaustion error, fast.
      def generate_from_regex(lengths)
        RegexGeneration.generate(
          @with_regexes.first,
          min_length: lengths.exact || lengths.minimum,
          max_length: [lengths.exact || lengths.maximum, @db_limit].compact.min
        )
      end

      def adjust_length(value, lengths)
        return value if value.nil?

        exact = lengths.exact
        maximum = lengths.maximum
        minimum = lengths.minimum

        # Exact length takes priority; a nil bound is an absent constraint.
        return set_to_length(value, exact) if exact

        value = truncate_to_length(value, maximum) if maximum && value.length > maximum
        value = pad_to_length(value, minimum) if minimum && value.length < minimum
        value = truncate_to_length(value, @db_limit) if @db_limit && value.length > @db_limit

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
        parts << "length constraints: #{length_options.inspect}" unless length_options.empty?
        parts.join('; ')
      end
    end
  end
end
