# frozen_string_literal: true

module FactoryBakery
  module Attachments
    module Adapters
      # The Active Storage adapter: attachment names come from the class's
      # attachment reflections, and the attachable is the hash Active Storage
      # builds a blob from. Building a blob writes nothing, so a plain `bake`
      # stays database-free and the file is uploaded when the record saves.
      module ActiveStorage
        module_function

        def available?(klass)
          defined?(::ActiveStorage) && klass.respond_to?(:attachment_reflections)
        end

        # Only single attachments are filled: a collection has no single file
        # to pick.
        def names(klass)
          klass.attachment_reflections.filter_map do |name, reflection|
            name if reflection.macro == :has_one_attached
          end
        end

        def presence_applies?(klass, name, record)
          Validation.presence_applies?(klass, name, record)
        end

        def allowed_content_types(klass, name)
          Validation.allowed_content_types(klass, name)
        end

        def attachable(name, fixture)
          {
            io: fixture.io,
            filename: fixture.filename_for(name),
            content_type: fixture.content_type
          }
        end
      end
    end
  end
end
