# frozen_string_literal: true

return unless defined?(Tapioca)
return unless defined?(Tapioca::Dsl::Compiler)

module Tapioca
  module Dsl
    module Compilers
      # Emits every recipe overload together under the FactoryBakery module.
      class FactoryBakery < Compiler
        COLUMN_TYPES = {
          string: '::String', text: '::String', integer: '::Integer', bigint: '::Integer',
          float: '::Float', decimal: '::BigDecimal', boolean: 'T::Boolean', date: '::Date',
          datetime: 'T.any(::Time, ::ActiveSupport::TimeWithZone)',
          timestamp: 'T.any(::Time, ::ActiveSupport::TimeWithZone)'
        }.freeze
        UNTYPED = 'T.untyped'
        BAKE_OPTIONS = { 'fill_optional' => UNTYPED, 'validate' => UNTYPED }.freeze
        RECIPE = '::FactoryBakery::Recipe'

        def self.gather_constants
          return [] unless defined?(::FactoryBakery::Sorbet)

          [::FactoryBakery]
        end

        def decorate
          # Specific overloads must precede those for their superclass and the generic fallback.
          models = registered_models.sort_by { |model| [-model.ancestors.length, model.name] }
          root.create_path(constant) do |namespace|
            create_recipe_entry(namespace, models)
            next if models.empty?

            namespace.create_class('Recipe') do |recipe|
              models.each { |model| create_model_recipe(recipe, model) }
            end
          end
        end

        private

        def registered_models
          return [] unless defined?(::ActiveRecord::Base)

          models = ::FactoryBakery::BakeryBuilder.definitions.map do |target, definition|
            target.is_a?(Symbol) ? definition.klass : target
          end
          records = models.grep(Class).select { |model| model < ::ActiveRecord::Base && model.name }
          records.uniq.reject(&:abstract_class?)
        end

        def recipe_name(model)
          # Escape underscores before flattening namespaces to keep the mapping one-to-one.
          "For#{model.name.gsub('_', '_0').gsub('::', '__')}"
        end

        def create_model_recipe(recipe, model)
          recipe.create_class(recipe_name(model), superclass_name: RECIPE) do |scope|
            model_type = "::#{model.name}"
            scope.create_type_variable('Model', type: 'type_member', fixed: model_type)

            trait_methods(model).each { |name| scope.create_method(name, return_type: 'T.self_type') }
            parameters = bake_parameters(model, model_type)
            scope.create_method('bake', parameters: parameters, return_type: model_type)
            scope.create_method('bake!', parameters: parameters, return_type: model_type)
          end
        end

        def trait_methods(model)
          existing = ::FactoryBakery::Recipe.public_instance_methods + ::FactoryBakery::Recipe.protected_instance_methods
          ::FactoryBakery.trait_names(model).map(&:to_s).select do |name|
            ::FactoryBakery::Recipe::TRAIT_NAME.match?(name) && name != 'initialize' && !existing.include?(name.to_sym)
          end
        end

        def bake_parameters(model, model_type)
          overrides = column_types(model).merge(association_types(model), BAKE_OPTIONS)
          overrides.select! { |name, _type| valid_parameter_name?(name) }
          parameters = overrides.sort.map do |name, type|
            create_kw_opt_param(name, type: as_nilable_type(type), default: 'nil')
          end

          block_name = 'blk'
          block_name = "_#{block_name}" while overrides.key?(block_name)
          parameters << create_block_param(block_name, type: "T.nilable(T.proc.params(record: #{model_type}).void)")
        end

        def column_types(model)
          return {} unless model.table_exists?

          model.columns.to_h do |column|
            type = COLUMN_TYPES.fetch(column.type, UNTYPED)
            type = "T::Array[#{type}]" if column.respond_to?(:array?) && column.array? && type != UNTYPED
            [column.name, type]
          end
        end

        def association_types(model)
          model.reflect_on_all_associations.to_h do |reflection|
            [reflection.name.to_s, association_type(reflection)]
          end
        end

        def association_type(reflection)
          return UNTYPED if reflection.polymorphic? || !reflection.klass.name

          type = "::#{reflection.klass.name}"
          reflection.collection? ? "T::Array[#{type}]" : type
        rescue NameError
          UNTYPED
        end

        def create_recipe_entry(namespace, models)
          namespace.create_method('recipe', class_method: true) do |method|
            arguments = create_rest_param('args', type: UNTYPED)
            method.params.concat([create_param('target', type: UNTYPED).param, arguments.param])
            models.each do |model|
              add_recipe_overload(method, arguments, "T.class_of(::#{model.name})", "#{RECIPE}::#{recipe_name(model)}")
            end
            add_recipe_overload(method, arguments, 'T::Class[T.type_parameter(:Model)]',
                                "#{RECIPE}[T.type_parameter(:Model)]",
                                type_params: ['Model'])
            add_recipe_overload(method, arguments, '::Symbol', "#{RECIPE}[#{UNTYPED}]")
          end
        end

        def add_recipe_overload(method, arguments, target_type, recipe_type, type_params: [])
          target = create_param('target', type: target_type)
          method.add_sig(params: [target.to_sig_param, arguments.to_sig_param], return_type: recipe_type,
                         type_params: type_params)
        end
      end
    end
  end
end
