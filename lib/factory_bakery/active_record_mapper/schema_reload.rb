# frozen_string_literal: true

module FactoryBakery
  module ActiveRecordMapper
    # Prepended to ActiveRecord::Base's singleton: when a model's schema is
    # reloaded (`reset_column_information`, a migration run in a console), the
    # facts cached about its columns and constraints are dropped with it. Rails
    # calls this on each subclass too, so they are cleared as well.
    module SchemaReload
      # The signature mirrors Rails' own, so the positional default stays.
      def reload_schema_from_cache(recursive = true) # rubocop:disable Style/OptionalBooleanParameter
        FactoryBakery::ClassCache.clear(self)
        super
      end

      protected :reload_schema_from_cache
    end
  end
end

ActiveRecord::Base.singleton_class.prepend(FactoryBakery::ActiveRecordMapper::SchemaReload) unless
  ActiveRecord::Base.singleton_class.ancestors.include?(FactoryBakery::ActiveRecordMapper::SchemaReload)
