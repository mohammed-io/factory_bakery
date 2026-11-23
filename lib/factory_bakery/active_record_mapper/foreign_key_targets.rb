# frozen_string_literal: true

module FactoryBakery
  module ActiveRecordMapper
    # Reads the database's foreign key constraints so a belongs_to can be
    # resolved from the table its column really references. Two callers use it:
    # AssociationIntrospection, for a class name with no constant, and
    # PolymorphicTargetDiscovery, to narrow a polymorphic candidate list.
    #
    # Constraints are read once per owner table for the process, in the style of
    # ReflectionCache, and dropped by PolymorphicTargetDiscovery.reset!. A read
    # that fails is not cached, so a later lookup can try again.
    module ForeignKeyTargets
      class << self
        # The table that the owner's constraint on `column` references, or nil
        # when no constraint covers that column. `column` may be a composite
        # key, given as an Array.
        def referenced_table(klass, column)
          constraints_for(klass).to_h[Array(column).map(&:to_s)]
        end

        # The one root model that stores `table`. STI subclasses share their
        # base's table, so they are ignored. nil when no loaded model, or more
        # than one, stores it.
        def model_for_table(table)
          roots = loaded_models.select { |model| stores?(model, table) && model.base_class == model }
          roots.size == 1 ? roots.first : nil
        end

        def stores?(model, table)
          model.respond_to?(:table_name) && model.table_name == table
        end

        def reset!
          @cache = {}
        end

        private

        def cache
          @cache ||= {}
        end

        def constraints_for(klass)
          cache[klass.table_name] ||= read(klass)
        end

        # Maps each constrained column (or composite column list) to the table
        # it references. nil when the adapter cannot report constraints.
        def read(klass)
          klass.connection.foreign_keys(klass.table_name).to_h do |foreign_key|
            [Array(foreign_key.column).map(&:to_s), foreign_key.to_table.to_s]
          end
        rescue StandardError, NotImplementedError
          nil
        end

        def loaded_models
          ::ActiveRecord::Base.descendants
        end
      end
    end
  end
end
