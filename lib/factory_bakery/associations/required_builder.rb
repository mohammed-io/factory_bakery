# frozen_string_literal: true

module FactoryBakery
  module Associations
    # Supplies :required_only auto-build values to core's heuristic_values hook.
    # Because they live in the heuristics layer, declarations, traits, overrides
    # and initialize_with keys of any alias-group member suppress them (core
    # expands the `taken` set to the whole group).
    module RequiredBuilder
      REFLECTION_PATH_KEY = :factory_bakery_associations_reflection_path

      class << self
        def values(klass, _context, taken)
          return {} unless Associations.mode == :required_only
          return {} unless klass.respond_to?(:reflect_on_all_associations)

          required_reflections(klass).each_with_object({}) do |reflection, values|
            name = reflection.name.to_s
            next if suppressed?(reflection, taken)

            require_target!(klass, reflection) if reflection.polymorphic?
            values[name] = build_parent(klass, reflection)
          end
        end

        private

        # Heuristic-first detection: Rails materializes "required" as a
        # PresenceValidator on the association name regardless of which setting
        # produced it (including on: :create and if:/unless:), and a NOT NULL FK
        # is required at the database level. `reflection.options[:optional]` is
        # deliberately never read -- plain ActiveRecord defaults it to optional.
        def required_reflections(klass)
          klass.reflect_on_all_associations(:belongs_to).select do |reflection|
            presence_validator?(klass, reflection) || not_null_fk?(klass, reflection)
          end
        end

        def presence_validator?(klass, reflection)
          klass.validators_on(reflection.name).any? do |validator|
            validator.is_a?(ActiveModel::Validations::PresenceValidator)
          end
        end

        def not_null_fk?(klass, reflection)
          return false unless klass.respond_to?(:columns_hash)

          Array(reflection.foreign_key).any? do |key|
            column = klass.columns_hash[key.to_s]
            column && !column.null
          end
        end

        def suppressed?(reflection, taken)
          alias_members(reflection).any? { |name| taken.include?(name) }
        end

        def alias_members(reflection)
          names = [reflection.name.to_s, *Array(reflection.foreign_key).map(&:to_s)]
          names << reflection.foreign_type.to_s if reflection.polymorphic?
          names.uniq
        end

        # The target class of a polymorphic belongs_to cannot be inferred from
        # the owner side without scanning every model for `as:`.
        def require_target!(klass, reflection)
          name = reflection.name
          raise FactoryBakery::Error,
                "#{klass}##{name} is a required polymorphic association; " \
                "declare it (e.g. association :#{name}, factory: SomeClass) or " \
                "pass #{name}: to name its target"
        end

        # Auto-built edges form a path of reflections (User#account ->
        # Account#owner -> ...). Re-encountering one means an insert cycle that
        # inverse_of cannot make persistable, so raise with the path and an
        # opt-out hint. A finite chain ended by a declaration never repeats an
        # edge and is allowed.
        def build_parent(klass, reflection)
          previous = reflection_path
          edge = "#{klass}##{reflection.name}"

          if previous.include?(edge)
            hint = previous.last.split('#').last
            raise CyclicAssociationError,
                  "#{(previous + [edge]).join(' -> ')}; " \
                  "declare one side (e.g. #{hint} { nil }) or make it optional"
          end

          Fiber[REFLECTION_PATH_KEY] = previous + [edge]
          FactoryBakery.bake(reflection.klass)
        ensure
          Fiber[REFLECTION_PATH_KEY] = previous
        end

        # Fiber-local so parallel/fiber-isolated bakes never share a path. The
        # array is replaced (not mutated) so a child fiber cannot alter its
        # parent's path; `ensure` in build_parent restores it after every edge.
        def reflection_path
          Fiber[REFLECTION_PATH_KEY] ||= [].freeze
        end
      end
    end
  end
end
