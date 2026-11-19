# frozen_string_literal: true

# Single seam for the Sequel side of the suite. Sequel keeps its OWN in-memory
# SQLite connection, fully separate from the suite's primary connection: one
# process proves both mappers coexist while neither framework shares state
# with the other.
#
# The sequel gem is a development-only dependency of the root Gemfile (never
# of the gemspec); appraisal gemfiles deliberately exclude it, so every
# Sequel group is tagged :sequel_mapper and reports itself skipped there
# rather than failing.
module SequelSupport
  class << self
    attr_reader :load_error

    # Loads the optional gem exactly once and remembers the failure, so the
    # suite never depends on gems the current gemfile does not include.
    def available?
      return @available unless @available.nil?

      require 'sequel'
      @available = true
    rescue LoadError => e
      @load_error = e
      @available = false
    end

    def db
      @db ||= ::Sequel.sqlite
    end

    # A pristine in-memory database per example: every model defined in a
    # let! block binds itself to the database that exists when it is created,
    # so examples can never observe each other's rows.
    def reset!
      @db = nil
    end
  end
end

# Model-defining macro for Sequel classes, mirroring DefineConstantMacros for
# the primary connection: it creates the table first (a Sequel class needs
# its schema before introspection), then defines and binds the model.
module DefineSequelModelMacros
  # Column shorthand shared by the Sequel specs: the macro turns it into the
  # Sequel create_table generator call for that type. Options pass through
  # unchanged (size:, null:, default:, unique: ...).
  COLUMN_TYPES = {
    string: ->(generator, name, opts) { generator.String(name, **opts) },
    text: ->(generator, name, opts) { generator.text(name, **opts) },
    integer: ->(generator, name, opts) { generator.Integer(name, **opts) },
    float: ->(generator, name, opts) { generator.Float(name, **opts) },
    decimal: ->(generator, name, opts) { generator.BigDecimal(name, **opts) },
    date: ->(generator, name, opts) { generator.Date(name, **opts) },
    datetime: ->(generator, name, opts) { generator.DateTime(name, **opts) },
    time: ->(generator, name, opts) { generator.Time(name, **opts) },
    boolean: ->(generator, name, opts) { generator.TrueClass(name, **opts) },
    json: ->(generator, name, opts) { generator.column(name, 'json', **opts) }
  }.freeze

  # `columns` may carry one :_index entry ({ columns: [...], unique: ... })
  # rendered as a dataset index; everything else is a column. The block is
  # class_eval'd on the model (plugins, stored validations, associations).
  def define_sequel_model(name, columns = {}, &block)
    spec = columns.dup
    index_spec = spec.delete(:_index)
    table_name = name.underscore.pluralize.to_sym
    db = SequelSupport.db
    db.drop_table?(table_name)
    db.create_table(table_name) do
      primary_key :id
      spec.each do |column_name, type_or_options|
        options = type_or_options.is_a?(Hash) ? type_or_options.dup : {}
        type = type_or_options.is_a?(Hash) ? options.delete(:type) : type_or_options
        COLUMN_TYPES.fetch(type).call(self, column_name, options)
      end
      if index_spec
        index(Array(index_spec[:columns]),
              unique: index_spec.fetch(:unique, true))
      end
    end

    model = stub_const(name, ::Sequel::Model(db[table_name]))
    model.class_eval(&block) if block
    model
  end

  def sequel_transaction_open?
    SequelSupport.db.in_transaction?
  end
end

RSpec.configure do |config|
  config.before(:each, :sequel_mapper) do
    unless SequelSupport.available?
      skip 'the sequel gem is not installed; it is a development-only dependency ' \
           'of the root Gemfile (never of the gemspec). Run the suite under the ' \
           'root Gemfile to exercise the Sequel mapper.'
    end
    SequelSupport.reset!
  end

  config.after(:each, :sequel_mapper) do
    SequelSupport.reset! if SequelSupport.available?
  end
end

# The Sequel groups exercise the plugin through its real require path. When
# the gem is absent (appraisal gemfiles deliberately exclude it), the groups
# report themselves skipped instead, so the require never fires there.
require 'factory_bakery/sequel' if SequelSupport.available?
