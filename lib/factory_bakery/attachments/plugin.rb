# frozen_string_literal: true

module FactoryBakery
  module Attachments
    # The plugin object registered with core on require. It marks every
    # attachment it means to fill in the heuristic layer (so the core's value
    # generators leave the name alone) and assigns the attachable after
    # instantiation, once declarations, overrides and initialize_with have run
    # and an if:/unless: guard can be evaluated for the record being baked.
    #
    # Nothing happens when neither attachment library is loaded, or for a class
    # that declares no attachment the adapter understands.
    module Plugin
      class << self
        def heuristic_values(klass, _context, taken)
          adapter = Adapter.for(klass)
          return {} unless adapter

          names = adapter.names(klass)
          return {} if names.empty?

          record = BuildContext.current_record
          names.each_with_object({}) do |name, values|
            next if taken.include?(name)
            next unless fill?(adapter, klass, name, record)

            values[name] = nil
          end
        end

        def after_instantiate(object, _declarations, context)
          adapter = Adapter.for(object.class)
          return unless adapter

          taken = Array(context.taken_names)
          adapter.names(object.class).each do |name|
            next if taken.include?(name)
            next unless fill?(adapter, object.class, name, object)

            object.public_send("#{name}=", adapter.attachable(name, fixture_for(adapter, object.class, name)))
          end
        end

        private

        def fill?(adapter, klass, name, record)
          FillOptional.includes?(FillOptional.current, name) ||
            adapter.presence_applies?(klass, name, record)
        end

        def fixture_for(adapter, klass, name)
          Fixtures.for(adapter.allowed_content_types(klass, name))
        end
      end
    end
  end
end
