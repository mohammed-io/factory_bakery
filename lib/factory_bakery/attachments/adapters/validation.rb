# frozen_string_literal: true

module FactoryBakery
  module Attachments
    module Adapters
      # The rule-reading both attachment libraries need: whether a presence
      # rule applies to the record being baked, and which content types an
      # attachment may hold. Reading validators off a class is a framework
      # read, so it lives here behind the adapters and never in the plugin.
      #
      # Conditions are resolved by the ORM mapper plugin's Conditional so
      # attachments share the mapper's semantics (ADR-0005) -- Symbol and
      # String predicates sent to the record, Procs instance_exec'd with the
      # record, and an unevaluable guard treated as applicable -- instead of
      # a second copy that drifts (and loses dirty tracking).
      module Validation
        # The option names the attachment validators use for their rule.
        CONTENT_TYPE_OPTIONS = %i[content_type with in].freeze

        module_function

        def presence_applies?(klass, name, record)
          validators_for(klass, name).any? do |validator|
            presence?(validator) && condition_applies?(validator, record, name)
          end
        end

        # Every content-type option the name's validators declare, flattened.
        # An attachment without one accepts any fixture, so the default wins.
        # Both spellings the attachment validators use are read: `content_type:`
        # (Paperclip and the earlier rule) and `with:` / `in:` (the current
        # rule). Rules the plugin cannot interpret -- a lazy Proc, for instance
        # -- are left out and fall back to the default fixture.
        def allowed_content_types(klass, name)
          validators_for(klass, name).filter_map do |validator|
            next nil unless content_type_validator?(validator)
            next nil unless validator.respond_to?(:options)

            CONTENT_TYPE_OPTIONS.filter_map { |key| validator.options[key] }
          end.flatten
        end

        def validators_for(klass, name)
          return [] unless klass.respond_to?(:validators_on)

          klass.validators_on(name)
        end
        private_class_method :validators_for

        def condition_applies?(validator, record, name)
          conditional = conditional_module
          return true unless conditional

          conditional.applies?(validator, record, name)
        end
        private_class_method :condition_applies?

        # The mapper plugin is loaded with the ORM; without it there are no
        # validators to read and no conditions to resolve.
        def conditional_module
          return nil unless defined?(FactoryBakery::ActiveRecordMapper::Conditional)

          FactoryBakery::ActiveRecordMapper::Conditional
        end
        private_class_method :conditional_module

        # Every presence validator an attachment library declares shares the
        # `PresenceValidator` suffix, so one name check covers them all.
        def presence?(validator)
          validator.class.name.to_s.end_with?('PresenceValidator')
        end
        private_class_method :presence?

        def content_type_validator?(validator)
          validator.class.name.to_s.end_with?('ContentTypeValidator')
        end
        private_class_method :content_type_validator?
      end
    end
  end
end
