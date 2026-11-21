# frozen_string_literal: true

module FactoryBakery
  # Text explaining why a built record is invalid: the invalid attributes, the
  # ones FactoryBakery filled at random (and the value it chose), the seed that
  # reproduces the run, and a snippet that pins the value in a definition. It
  # reads the record's errors and provenance and never runs validations itself,
  # so the caller decides when `valid?` ran.
  class Explanation
    NOT_GENERATED = 'This record was not built by FactoryBakery; no value came from it at random.'
    NO_RANDOM_CULPRIT = 'No invalid attribute was generated at random: check your declarations and overrides.'

    def self.errors?(record)
      record.respond_to?(:errors) && !record.errors.empty?
    end

    # Runs a save. When it fails with the record's errors in place, the error
    # is re-raised as the same exception class (`exception` clones it) with the
    # explanation appended after the original message. Nothing is retried.
    def self.around_failed_save(record)
      yield
    rescue StandardError => e
      raise unless errors?(record)

      raise e.exception("#{e.message}\n\n#{new(record).text}")
    end

    def initialize(record)
      @record = record
    end

    def text
      origin = Provenance.of(@record)
      [header, *error_lines, *(origin ? generated_lines(origin) : [NOT_GENERATED])].join("\n")
    end

    private

    def header
      "FactoryBakery could not produce a valid #{class_name}. Invalid attributes:"
    end

    def error_lines
      error_pairs.map { |attribute, message| "  - #{attribute}: #{message}" }
    end

    def generated_lines(origin)
      chosen = involved(origin)
      return [seed_line(origin), NO_RANDOM_CULPRIT] if chosen.empty?

      [
        seed_line(origin), *chosen_lines(chosen), '',
        "To make the value deterministic, pin it in #{definition_file}:", '',
        *snippet(chosen), '', agent_line(origin)
      ]
    end

    def seed_line(origin)
      line = "Seed #{origin.seed.value} from #{origin.seed.description}. Reproduce: #{origin.seed.reproduce_hint}"
      return line unless origin.ordinal

      "#{line} (top-level bake ##{origin.ordinal + 1} of #{origin.model} in this process; " \
        'the same seed needs the same bakes in the same order)'
    end

    # Filled attributes an error names: directly, or through a base error whose
    # message mentions them. Each entry is [name, named_in_base_error?].
    def involved(origin)
      origin.filled.filter_map do |name|
        if error_pairs.any? { |attribute, _| attribute == name }
          [name, false]
        elsif named_in_base_error?(name)
          [name, true]
        end
      end
    end

    def named_in_base_error?(name)
      pattern = /\b(?:#{Regexp.escape(name)}|#{Regexp.escape(name.tr('_', ' '))})\b/i
      error_pairs.any? { |attribute, message| attribute == 'base' && message.match?(pattern) }
    end

    def chosen_lines(chosen)
      chosen.map do |name, via_base|
        suffix = via_base ? ' (named in a base error)' : ''
        "Chosen at random: #{name} = #{value_of(name).inspect}#{suffix}"
      end
    end

    def snippet(chosen)
      [
        "FactoryBakery.define(#{class_name}) do",
        *chosen.map do |name, _|
          "  #{name} { nil } # was randomly #{value_of(name).inspect}; use a value your validations accept"
        end,
        'end'
      ]
    end

    def agent_line(origin)
      requirements = error_pairs.map { |attribute, message| attribute == 'base' ? message : "#{attribute} #{message}" }
      "Agent: edit #{definition_file}, add the block above inside FactoryBakery.define(#{class_name}), " \
        "choose values that satisfy #{requirements.join('; ')}, then re-run with #{origin.seed.reproduce_hint}"
    end

    # [attribute, message] pairs. An errors collection of Error objects is
    # enumerated as-is; a Hash-shaped one maps each attribute to its messages.
    def error_pairs
      @error_pairs ||= begin
        errors = @record.errors
        if errors.is_a?(Hash)
          errors.flat_map { |attribute, messages| Array(messages).map { |message| [attribute.to_s, message.to_s] } }
        else
          errors.map { |error| [error.attribute.to_s, error.message.to_s] }
        end
      end
    end

    def value_of(name)
      @record.respond_to?(name) ? @record.public_send(name) : nil
    end

    def class_name
      klass = @record.class
      klass.name || klass.inspect
    end

    def definition_file
      root = Array(FactoryBakery.definition_paths).first
      return 'your definitions file' unless root

      File.join(root.to_s, "#{underscore(class_name)}.rb")
    end

    def underscore(name)
      name.gsub('::', '/').gsub(/([A-Z\d]+)([A-Z][a-z])/, '\1_\2')
          .gsub(/([a-z\d])([A-Z])/, '\1_\2').tr('-', '_').downcase
    end
  end
end
