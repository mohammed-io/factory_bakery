# frozen_string_literal: true

module FactoryBakery
  module ActiveRecordMapper
    # A belongs_to whose `primary_key:` points at a column other than the
    # target's own primary key (issue #54). Its FK is ordinary data the child
    # can generate itself, not a reference to a freshly built parent's id, so
    # it is treated differently for guard columns and required-ness.
    #
    # Composite and absent options stay on the ordinary id-keyed path. All
    # framework reflection is read here; callers receive plain booleans/names.
    module NaturalKey
      module_function

      def natural?(reflection)
        !key_name(reflection).nil?
      end

      def key_name(reflection)
        key = reflection.options[:primary_key]
        return nil if key.nil? || key.is_a?(Array)
        return nil if key.to_s == reflection.klass.primary_key.to_s

        key.to_s
      rescue StandardError
        nil
      end
    end
  end
end
