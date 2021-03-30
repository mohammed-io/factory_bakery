module FactoryBakery
  module GeneratorRegistry
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def registry
        @registry ||= {}
      end

      def register(type, value = nil, &block)
        registry[type.to_sym] = if block_given?
                                  block
                                else
                                  proc { value }
                                end
      end

      def random_choice(choices)
        choices[rand(choices.count - 1)]
      end

      def choices_or_else(descriptor)
        if descriptor.choices
          random_choice descriptor.choices
        elsif block_given?
          yield
        end
      end
    end

    def registry
      self.class.registry
    end
  end
end