# frozen_string_literal: true

module FactoryBakery
  module ActiveRecordMapper
    # A database index can require a plain text column to hold JSON even when
    # the column's own type is `varchar` or `text`: PostgreSQL evaluates an
    # expression index such as
    #
    #   CREATE INDEX ... ON notifications (((data)::jsonb ->> 'username'::text))
    #
    # against every inserted row, so a non-JSON string is rejected with
    # "invalid input syntax for type json" (Discourse's `notifications.data`,
    # a `varchar(1000)`).
    #
    # This module is the one pure function that recognizes such a cast. It
    # takes the SQL strings a mapper reports (an expression index's columns and
    # its partial-index predicate) and answers the column names the database
    # reads as JSON. Framework reads live in the mapper; the function itself
    # only matches text, so it is unit-testable on the real SQL shapes.
    module JsonCast
      # A cast target, with the type name optionally schema-qualified and
      # optionally carrying a type modifier (`pg_catalog.jsonb(4096)`). The
      # trailing boundary keeps `jsonb_extra` from reading as `jsonb`.
      TYPE = /(?:pg_catalog\.)?jsonb?(?:\s*\(\s*\d+\s*\))?\b/i

      # `col::json`, `"col"::jsonb`, `((data))::jsonb` -- a column (possibly
      # wrapped in the parentheses an expression index adds) followed by `::`
      # and the type.
      COLON_PATTERN = /\(*\s*"?(?<column>[a-z_][a-z0-9_]*)"?\s*\)*\s*::\s*#{TYPE}/i

      # `CAST(col AS json[b])`, with the column optionally quoted.
      CAST_PATTERN = /cast\s*\(\s*"?(?<column>[a-z_][a-z0-9_]*)"?\s+as\s+#{TYPE}\s*\)/i

      module_function

      # Column names the given SQL strings cast to json/jsonb, downcased and
      # de-duplicated. Anything that is not a String (a plain index column
      # name, nil) contributes nothing.
      def columns_in(*statements)
        statements.compact.map(&:to_s).flat_map { |sql| casts_in(sql) }.uniq
      end

      def casts_in(sql)
        [COLON_PATTERN, CAST_PATTERN].flat_map do |pattern|
          sql.scan(pattern).map { |match| match.first.downcase }
        end
      end
      private_class_method :casts_in
    end
  end
end
