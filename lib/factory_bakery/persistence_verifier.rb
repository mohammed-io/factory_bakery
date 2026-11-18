# frozen_string_literal: true

module FactoryBakery
  # After the root `save!`, checks that every record generated anywhere in the
  # bake graph actually reached the database. Rails autosave options such as
  # `autosave: false` or `validate: false` can leave an associated object new
  # even though the root saved successfully; returning such a graph would hand
  # the caller a half-persisted object.
  class PersistenceVerifier
    def initialize(root, entries)
      @root = root
      @entries = entries
    end

    def call
      unsaved = @entries.reject { |_path, record| persisted?(record) }
      return if unsaved.empty?

      raise IncompletePersistenceError, message_for(unsaved)
    end

    private

    def persisted?(record)
      !record.respond_to?(:new_record?) || !record.new_record?
    end

    def message_for(unsaved)
      objects = [@root, *@entries.map { |_path, record| record }].uniq

      details = unsaved.map do |_path, record|
        name = record.class.name || record.class.to_s
        association = association_name_for(record, objects)
        association ? "#{name} (assigned to #{association})" : name
      end

      "bake! did not persist all generated records: #{details.join(', ')}. " \
        'Persist the record explicitly via a declaration or override, ' \
        "or change the association's autosave/validate options."
    end

    # Best-effort name of the association the unsaved record hangs off. The
    # object graph is the source of truth here, so this also works for records
    # supplied through call-site overrides rather than declaration blocks.
    def association_name_for(record, objects)
      objects.each do |object|
        next unless object.class.respond_to?(:reflect_on_all_associations)

        name = association_on(object, record)
        return name if name
      end
      nil
    end

    def association_on(object, record)
      object.class.reflect_on_all_associations.each do |reflection|
        next unless object.respond_to?(reflection.name)

        value = associated_value(object, reflection.name)
        next if value.nil?

        candidates = value.respond_to?(:target) ? value.target : [value]
        return reflection.name.to_s if Array(candidates).any? { |candidate| candidate.equal?(record) }
      end
      nil
    end

    def associated_value(object, name)
      object.public_send(name)
    rescue StandardError
      nil
    end
  end
end
