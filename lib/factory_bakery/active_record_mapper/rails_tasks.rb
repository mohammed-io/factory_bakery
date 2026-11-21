# frozen_string_literal: true

module FactoryBakery
  module ActiveRecordMapper
    # Selects application models, checks their bakes and writes definition stubs.
    class RailsTasks # rubocop:disable Metrics/ClassLength
      DIAGNOSTICS_URL = 'https://github.com/mohammed-io/factory_bakery/blob/main/docs/diagnostics.md'

      # Each entry maps a failure to a hint and a heading anchor in docs/diagnostics.md.
      HINTS = {
        /could not generate a unique value/i => [
          'Declare a value that varies across bakes.', 'unique-value-collisions'
        ],
        /no target discovered/i => [
          'Declare the association and its target class.', 'no-polymorphic-target-discovered'
        ],
        /IncompletePersistenceError/ => [
          'Check whether the associated records can be saved.', 'incomplete-persistence'
        ],
        /NotNullViolation|InvalidForeignKey/ => [
          'Declare values or associations required by the database.', 'db-only-constraints'
        ],
        /Chosen at random:/ => ['Pin the generated value in a definition.', 'random-value-rejected-by-app-rule'],
        // => [
          'Check the model validations and callbacks, then declare any required overrides.',
          'domain-rules-inference-cannot-know'
        ]
      }.freeze

      def initialize(app)
        @app = app
      end

      def definitions(names)
        models = selected_models(names)
        models = models.reject { |model| BakeryBuilder.definitions.key?(model) } if names.empty?
        models.each { |model| write_definition(model) }
      end

      def doctor(names)
        models = selected_models(names)
        failures = collect_failures(models)
        failures.each { |model, error| report_failure(model, error) }
        puts "#{models.size - failures.size} valid, #{failures.size} needs definition"
        exit 1 if failures.any? && ENV['NO_FAIL'] != '1'
      end

      private

      def collect_failures(models)
        pools = ActiveRecord::Base.connection_handler.connection_pool_list(ActiveRecord::Base.current_role)
        failures = {}
        rollback(pools) do
          failures = models.filter_map do |model|
            error = check_model(model, pools)
            [model, error] if error
          end.to_h
        end
        failures
      end

      def selected_models(names)
        return names.map { |name| active_record_model(name) }.uniq if names.any?

        @app.eager_load!
        ActiveRecord::Base.descendants.select do |model|
          model.name && !model.abstract_class? && model.name.safe_constantize.equal?(model)
        end.sort_by(&:name)
      end

      def active_record_model(name)
        model = name.safe_constantize
        return model if model.is_a?(Class) && model < ActiveRecord::Base && !model.abstract_class?

        abort "Unknown concrete Active Record model: #{name}"
      end

      def write_definition(model, diagnostic = nil)
        require 'generators/factory_bakery/definition/definition_generator'
        generator = Generators::DefinitionGenerator.new([model.name], [], destination_root: @app.root.to_s)
        generator.diagnostic = diagnostic
        generator.invoke_all
      end

      def check_model(model, pools)
        validation_error = probe(pools) do
          record = FactoryBakery.bake(model)
          next if record.valid?

          summary = record.errors.full_messages.first || 'Validation failed'
          raise FactoryBakery::Error, "#{summary}\n#{FactoryBakery.explain(record)}"
        end
        persistence_error = probe(pools) do
          record = FactoryBakery.bake!(model)
          raise FactoryBakery::IncompletePersistenceError, 'bake! did not persist the record' unless record&.persisted?
        end
        validation_error || persistence_error
      end

      def probe(pools, &block)
        rollback(pools, &block)
        nil
      rescue StandardError => e
        e
      end

      def rollback(pools, &block)
        pools.reverse_each.reduce(block) do |operation, pool|
          lambda do
            pool.with_connection do |connection|
              connection.transaction(requires_new: true) do
                operation.call
                raise ActiveRecord::Rollback
              end
            end
          end
        end.call
      end

      def report_failure(model, error)
        message = "#{error.class}: #{error.message}"
        _, (hint, anchor) = HINTS.find { |pattern, _| pattern.match?(message) }
        summary, *details = error.message.lines.map(&:chomp)
        puts "#{model.name}: #{summary} — #{hint} (#{DIAGNOSTICS_URL}##{anchor})"
        details.each { |line| puts "  #{line}" }
        write_definition(model, error.message) if ENV['WRITE'] == '1'
      end
    end
  end
end
