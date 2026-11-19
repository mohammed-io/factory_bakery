# frozen_string_literal: true

module FactoryBakery
  module ActiveRecordMapper
    # Construction fallbacks for models whose ordinary constructor raises
    # (issue #56). Some real-world models cannot be instantiated with `new` at
    # all: a `default_scope` that raises while Rails applies its create
    # attributes, or an `after_initialize` callback that raises. Both can still
    # be populated, so construction retries in a fixed order:
    #
    #   1. the ordinary constructor (the caller's block),
    #   2. `unscoped { ... }`, which skips the default scope but keeps
    #      `after_initialize` defaults,
    #   3. callback-free construction, which skips `after_initialize` too.
    #
    # The order matters: step 3 drops app-defined initialization, so it is only
    # a last resort. Step 3 depends on framework internals, so it is guarded by
    # a capability check: when they are missing it is skipped and the original
    # error is re-raised.
    module Construction
      # Instance methods callback-free construction relies on. They exist on
      # every Rails version this gem supports (see the Appraisals matrix), but
      # the check is explicit so a version that moves them skips the strategy
      # instead of failing.
      CALLBACK_FREE_METHODS = %i[init_internals initialize_internals_callback].freeze

      module_function

      # Builds one instance of +klass+. The block performs the ordinary
      # construction (constructor arguments included); +apply+ assigns the
      # caller's constructor attributes to an object a fallback built without
      # running the constructor.
      def call(klass, apply: nil, &build)
        build.call
      rescue StandardError => e
        retry_with_fallbacks(klass, e, apply, &build)
      end

      # Only falls back when the previous step raised. When no strategy applies
      # (a plain object, or framework internals this version does not have) the
      # original error is re-raised untouched.
      def retry_with_fallbacks(klass, original, apply, &build)
        attempted = []
        object = unscoped_construction(klass, attempted, &build)
        object = callback_free_construction(klass, attempted, apply) if object.nil?
        return object unless object.nil?

        raise annotated(original, attempted)
      end

      def unscoped_construction(klass, attempted, &build)
        return nil unless klass.respond_to?(:unscoped)

        attempted << 'unscoped'
        klass.unscoped { build.call }
      rescue StandardError
        nil
      end

      def callback_free_construction(klass, attempted, apply)
        return nil unless callback_free_capable?(klass)

        attempted << 'callback-free'
        callback_free_new(klass, apply)
      rescue StandardError
        nil
      end

      # Rails' own `initialize` without the initialize callbacks: allocate,
      # restore the default attributes, and run the framework's internal setup.
      def callback_free_new(klass, apply)
        object = klass.allocate
        object.instance_variable_set(:@new_record, true)
        object.instance_variable_set(:@attributes, klass._default_attributes.deep_dup)
        object.send(:init_internals)
        object.send(:initialize_internals_callback)
        apply&.call(object)
        object
      end

      def callback_free_capable?(klass)
        active_record_class?(klass) &&
          klass.respond_to?(:_default_attributes) &&
          CALLBACK_FREE_METHODS.all? { |name| klass.method_defined?(name) || klass.private_method_defined?(name) }
      end

      # A callback-free copy of +record+ for probes that must not run the
      # initialize callbacks. `dup` runs them, so it raises for the same models
      # the construction fallback exists for (issue #56).
      def copy(record)
        object = record.class.allocate
        object.instance_variable_set(:@new_record, record.new_record?)
        object.instance_variable_set(:@attributes, record.instance_variable_get(:@attributes).deep_dup)
        object.send(:init_internals)
        object.send(:initialize_internals_callback)
        object
      end

      def active_record_class?(klass)
        defined?(::ActiveRecord::Base) && klass < ::ActiveRecord::Base
      end

      # Keeps the original class, backtrace and any extra state (an
      # ActiveRecord error's record or SQL), so the app still sees the real
      # failure; the note only records that fallbacks were tried.
      def annotated(error, attempted)
        return error if attempted.empty?

        error.exception("#{error.message} (FactoryBakery also tried #{attempted.join(' and ')} construction)")
      end
    end
  end
end
