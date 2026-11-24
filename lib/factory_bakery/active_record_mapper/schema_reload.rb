# frozen_string_literal: true

module FactoryBakery
  module ActiveRecordMapper
    # Prepended to ActiveRecord::Base's singleton: when a model's schema is
    # reloaded (`reset_column_information`, a migration run in a console), the
    # facts cached about its columns and constraints are dropped with it. Rails
    # calls this on each subclass too, so they are cleared as well.
    module SchemaReload
      # The signature mirrors Rails' own, so the positional default stays.
      # The cache is cleared only after Rails has reloaded its own schema, so
      # a computation that runs during the reload reads the new schema rather
      # than recomputing against the old one.
      def reload_schema_from_cache(recursive = true) # rubocop:disable Style/OptionalBooleanParameter
        result = super
        FactoryBakery::ClassCache.clear(self)
        result
      end

      protected :reload_schema_from_cache
    end
  end
end

# Installed lazily: the gem may be required before the host app has finished
# configuring itself, and touching ActiveRecord::Base here would run Rails'
# `on_load(:active_record)` hooks too soon (e.g. before the app's own Active
# Record encryption settings exist). Inside the hook `self` is ActiveRecord::Base.
ActiveSupport.on_load(:active_record) do
  singleton_class.prepend(FactoryBakery::ActiveRecordMapper::SchemaReload) unless
    singleton_class.ancestors.include?(FactoryBakery::ActiveRecordMapper::SchemaReload)
end
