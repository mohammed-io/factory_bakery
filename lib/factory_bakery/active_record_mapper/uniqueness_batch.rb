# frozen_string_literal: true

module FactoryBakery
  module ActiveRecordMapper
    # One round trip for all of a record's plain unique columns instead of one
    # per column: `SELECT EXISTS(SELECT 1 FROM t WHERE a = $1), EXISTS(...)`,
    # with every value a bind parameter. It answers only what it can answer
    # exactly: an attribute is batched solely when it is a real scalar column
    # guarded by a case-sensitive, unscoped uniqueness validator declared on
    # the record's own class, the adapter runs prepared statements, and no STI
    # type condition would change the query. Anything else is simply absent
    # from the answer, and the caller falls back to UniquenessProbe, which
    # asks the model's own validator one column at a time. Values never travel
    # as SQL text: the cached statement holds identifiers and placeholders
    # only, and the values are bound on execution.
    #
    # Validators carrying `if:` / `unless:` conditions are batched exactly as
    # the per-column probe would answer them: both ask the column and neither
    # evaluates the condition (the probe runs `validate_each` directly), so
    # the batch's answer is the same fact the probe would return.
    #
    # On MySQL/Trilogy a plain `=` can be case-insensitive under the default
    # collation, so the batch may report a value as taken that a case-sensitive
    # validator would accept; the only effect is an unnecessary regeneration,
    # never a missed collision.
    module UniquenessBatch
      BATCHABLE_ADAPTERS = %w[SQLite PostgreSQL Mysql2 Trilogy].freeze
      BATCHABLE_TYPES = %i[string text integer bigint uuid decimal float date datetime boolean].freeze
      # Options a batchable validator may carry; `:case_sensitive` must
      # additionally be nil or true, so the batch's `=` matches the validator.
      PLAIN_VALIDATOR_OPTIONS = %i[message allow_nil allow_blank if unless on except_on case_sensitive].freeze

      class << self
        # { 'attr_name' => true/false } for exactly the attributes the batch
        # can answer. An attribute it cannot answer exactly is absent, and the
        # caller asks the per-column probe for it instead.
        def taken(record, values, validators_by_attribute)
          return {} if record.respond_to?(:persisted?) && record.persisted?

          batchable = values.select do |attribute, value|
            batchable?(record, attribute, value, validators_by_attribute[attribute])
          end
          return {} if batchable.empty?

          answer(record, batchable)
        end

        private

        def batchable?(record, attribute, value, validators)
          klass = record.class
          return false unless connection_batchable?(klass)
          return false if value.nil?
          return false unless plain_validators?(validators)
          return false unless declared_on_klass?(klass, attribute, validators)
          return false unless plain_column?(klass, attribute)

          true
        end

        # Raw `?`/`$n` placeholders with bound values only behave like the
        # adapter's own prepared statements, so adapters that default them
        # off (and anything unknown) keep the per-column probe.
        def connection_batchable?(klass)
          return false unless klass.respond_to?(:connection)

          connection = klass.connection
          return false unless connection.respond_to?(:prepared_statements) && connection.prepared_statements

          BATCHABLE_ADAPTERS.include?(connection.adapter_name)
        end

        def plain_validators?(validators)
          return false if validators.empty?

          validators.all? do |validator|
            # Only Rails' own UniquenessValidator is batched. A subclass may
            # override `validate_each` (folding case, adding conditions), and
            # the batch's plain `=` would answer a different question than its
            # probe would.
            return false unless validator.instance_of?(::ActiveRecord::Validations::UniquenessValidator)

            validator.options.all? { |key, value| plain_option?(key, value) }
          end
        end

        def plain_option?(key, value)
          return false unless PLAIN_VALIDATOR_OPTIONS.include?(key)
          # Only an omitted `case_sensitive` or an explicit `true` means the
          # adapter's plain `=` comparison. An explicit `nil` asks Rails for
          # its case-insensitive comparison, and `false` folds case -- neither
          # matches the batch's statement.
          return false if key == :case_sensitive && value != true

          true
        end

        # A validator inherited from a superclass queries its declaring class,
        # which the batch does not reproduce, so only validators declared on
        # `klass` itself are batchable. An STI type condition would likewise
        # change the query.
        def declared_on_klass?(klass, attribute, validators)
          return false if klass.respond_to?(:finder_needs_type_condition?) && klass.finder_needs_type_condition?

          inherited = superclass_validators(klass, attribute)
          own = klass.validators_on(attribute).reject { |candidate| inherited.any? { |other| other.equal?(candidate) } }
          validators.all? { |validator| own.any? { |candidate| candidate.equal?(validator) } }
        end

        def superclass_validators(klass, attribute)
          return [] unless klass.superclass.respond_to?(:validators_on)

          klass.superclass.validators_on(attribute)
        end

        def plain_column?(klass, attribute)
          return false unless klass.column_names.include?(attribute)
          return false unless BATCHABLE_TYPES.include?(klass.type_for_attribute(attribute).type)
          return false if encrypted_attribute?(klass, attribute)
          return false if klass.defined_enums.key?(attribute)

          true
        end

        def encrypted_attribute?(klass, attribute)
          klass.respond_to?(:encrypted_attributes) && klass.encrypted_attributes&.include?(attribute.to_sym)
        end

        # One positional row: cell i answers attributes[i]. A nil row (an
        # adapter that answers nothing) leaves everything to the probe.
        def answer(record, batchable)
          klass = record.class
          connection = klass.connection
          attributes = batchable.keys
          sql = cached_sql(klass, connection, attributes)
          row = connection.select_rows(sql, 'FactoryBakery uniqueness', binds(klass, batchable)).first
          return {} if row.nil?

          attributes.zip(row).to_h { |attribute, cell| [attribute, taken_cell?(cell)] }
        end

        # Cells answer the same fact in every adapter's spelling.
        TAKEN_CELLS = [true, 1, '1', 't'].freeze

        def taken_cell?(cell)
          TAKEN_CELLS.include?(cell)
        end

        def binds(klass, batchable)
          batchable.map do |attribute, value|
            ::ActiveRecord::Relation::QueryAttribute.new(attribute, value, klass.type_for_attribute(attribute))
          end
        end

        # The statement is a pure function of the adapter's placeholder
        # spelling, the table and the ordered attributes (identifiers and
        # placeholders, never a value), so the cache is keyed on all three:
        # one class baked under a SQLite role and then a Postgres role must
        # not reuse the other adapter's placeholders.
        def cached_sql(klass, connection, attributes)
          FactoryBakery::ClassCache
            .table(klass, FactoryBakery::ClassCache::UNIQUENESS_BATCH)[batch_key(klass, connection, attributes)] ||=
            build_sql(klass, connection, attributes)
        end

        def batch_key(klass, connection, attributes)
          [connection.adapter_name, klass.table_name, attributes.join(',')].join("\0")
        end

        def build_sql(klass, connection, attributes)
          table = connection.quote_table_name(klass.table_name)
          clauses = attributes.each_with_index.map do |attribute, index|
            column = connection.quote_column_name(attribute)
            "EXISTS(SELECT 1 FROM #{table} WHERE #{column} = #{placeholder(connection, index)})"
          end
          "SELECT #{clauses.join(', ')}"
        end

        def placeholder(connection, index)
          connection.adapter_name == 'PostgreSQL' ? "$#{index + 1}" : '?'
        end
      end
    end
  end
end
