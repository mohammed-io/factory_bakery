# frozen_string_literal: true

require 'active_record'
require_relative '../database'

module DefineConstantMacros
  def define_class(path, base = Object, &block)
    const = if defined?(stub_const)
              stub_const(path, Class.new(base))
            else
              # When running outside of the test suite.
              Object.const_set(path, Class.new(base))
            end

    # Use class_eval after class creation for better compatibility
    const.class_eval(&block) if block

    # Track for cleanup
    created_constants << path
    created_classes << const if base == ActiveRecord::Base

    const
  end

  def define_model(name, columns = {}, &block)
    # Create table first (needed for enum support)
    # Lowercase plural names match ActiveRecord's own conventions and keep
    # foreign keys resolvable on case-sensitive databases (PostgreSQL).
    table_name = ActiveRecord::Base.table_name_prefix + name.underscore.pluralize

    connection = ActiveRecord::Base.connection
    connection.drop_table(table_name, if_exists: true)
    connection.create_table(table_name) do |table|
      columns.each do |column_name, type_or_options|
        if type_or_options.is_a?(Hash)
          # Support { type: :string, limit: 8 } syntax
          column_type = type_or_options.delete(:type)
          table.column(column_name, DatabaseSupport.column_type(column_type), **type_or_options)
        else
          # Support simple :string syntax
          table.column column_name, DatabaseSupport.column_type(type_or_options)
        end
      end
    end

    # Then define the model class
    const = if defined?(stub_const)
              stub_const(name, Class.new(ActiveRecord::Base))
            else
              Object.const_set(name, Class.new(ActiveRecord::Base))
            end

    # Set the table name explicitly
    const.table_name = table_name

    # Evaluate the block after the class is created and table exists
    const.class_eval(&block) if block

    # Store for cleanup
    created_tables << table_name
    created_constants << name
    created_classes << const

    const
  end

  def create_table(table_name, &block)
    connection = ActiveRecord::Base.connection

    begin
      connection.drop_table(table_name, if_exists: true)
      connection.create_table(table_name, &block)
      created_tables << table_name
      connection
    rescue Exception => e # rubocop:disable Lint::RescueException
      connection.drop_table(table_name, if_exists: true)
      raise e
    end
  end

  def cleanup_model(name)
    # Remove the constant (let RSpec's stub_const handle it if it was stubbed)
    if Object.const_defined?(name)
      Object.send(:remove_const, name) unless defined?(stub_const)
    end

    # Drop the table
    table_name = name.pluralize
    ActiveRecord::Base.connection.drop_table(table_name, if_exists: true)

    # Remove from tracking
    created_constants.delete(name)
    created_tables.delete(table_name)
    created_classes.reject! { |klass| klass.name.to_s == name.to_s }
  end

  def clear_generated_tables
    # Drop in reverse creation order: children are created after their
    # parents, and real FK constraints reject dropping a referenced parent.
    created_tables.reverse_each do |table_name|
      ActiveRecord::Base.connection.drop_table(table_name, if_exists: true)
    end
    created_tables.clear

    # Clear tracking arrays (but don't manually remove constants - RSpec handles it)
    created_constants.clear
    created_classes.clear
  end

  def clear_generated_table(table_name)
    ActiveRecord::Base.connection.drop_table(table_name, if_exists: true)
  end

  private

  def created_tables
    @created_tables ||= []
  end

  def created_constants
    @created_constants ||= []
  end

  def created_classes
    @created_classes ||= []
  end
end

RSpec.configure do |config|
  config.include DefineConstantMacros

  config.before(:all) do
    DatabaseSupport.establish_connection!
  end

  config.after do
    clear_generated_tables
  end
end
