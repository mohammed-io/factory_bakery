# frozen_string_literal: true

module FactoryBakery
  # The default-bake rule: heuristics fill only the attributes a valid record
  # needs, leaving optional ones at their default or nil. The decision reads
  # only normalized ConstraintSet facts; all framework reflection stays in the
  # mapper (ADR-0001) and conditions were resolved there for this record
  # (ADR-0005).
  module RequiredAttribute
    module_function

    def call(constraints)
      return virtual_required?(constraints) unless constraints.column_backed
      return true if !constraints.nullable && !constraints.has_default

      return constraints.must_be_present && blank_default?(constraints.default_value) if constraints.has_default

      constraints.nil_rejected
    end

    # A virtual attribute has no schema to make it required, so it follows the
    # same rule as a nullable column: an applicable validator that rejects nil
    # makes it needed. Acceptance and confirmation are the exceptions: both
    # tolerate nil by default, yet they only mean something with a value (the
    # accepted value itself, and the source a confirmation twin copies), so a
    # virtual attribute carrying one is still filled.
    def virtual_required?(constraints)
      constraints.nil_rejected || constraints.acceptance_validated || constraints.confirmation_validated
    end

    # Matches the common meaning of a blank default: nil, false and strings
    # that hold nothing but whitespace. A non-blank default is kept as-is.
    def blank_default?(value)
      value.nil? || value == false || value.to_s.strip.empty?
    end
  end
end
