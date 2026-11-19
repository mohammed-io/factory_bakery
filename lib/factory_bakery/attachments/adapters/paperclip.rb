# frozen_string_literal: true

module FactoryBakery
  module Attachments
    module Adapters
      # The Paperclip adapter. Attachment names come from the model's
      # attachment definitions and the attachable is the fixture file itself,
      # which is what Paperclip's file adapter reads.
      module Paperclip
        module_function

        def available?(klass)
          defined?(::Paperclip) && klass.respond_to?(:attachment_definitions) &&
            !klass.attachment_definitions.empty?
        end

        def names(klass)
          klass.attachment_definitions.keys.map(&:to_s)
        end

        def presence_applies?(klass, name, record)
          Validation.presence_applies?(klass, name, record)
        end

        def allowed_content_types(klass, name)
          Validation.allowed_content_types(klass, name)
        end

        def attachable(_name, fixture)
          File.open(fixture.path, 'rb')
        end
      end
    end
  end
end
