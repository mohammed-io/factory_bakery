# frozen_string_literal: true

module FactoryBakery
  # Each build attempt gets its own memo and evaluation stack.
  class DeclarationValues
    # Keep zero-argument reads distinct from calls to the declaration DSL,
    # including when an attribute shares a DSL method's name.
    class Scope < BasicObject
      def initialize(builder, object, names, &read)
        @builder = builder
        @object = object
        @names = names
        @read = read
      end

      private

      def method_missing(name, *args, **kwargs, &block)
        key = name.to_s
        return @read.call(key) if args.empty? && kwargs.empty? && !block && attribute?(key)

        @builder.__send__(name, *args, **kwargs, &block)
      end

      def respond_to_missing?(name, include_private)
        attribute?(name.to_s) || @builder.respond_to?(name, include_private)
      end

      def attribute?(name)
        @names.include?(name) || @object.respond_to?("#{name}=")
      end
    end

    def initialize(builder, object, blocks, known_names, &read)
      @blocks = blocks
      @read = read
      @values = {}
      @resolving = []
      @scope = Scope.new(builder, object, known_names) { |name| resolve(name) }
    end

    def resolve_all
      @blocks.each_key { |name| resolve(name) }
      @values
    end

    def bind_to(resolver)
      resolver.bind_declarations(@blocks.keys) { |name| resolve(name) }
    end

    private

    def resolve(name)
      return @values[name] if @values.key?(name)

      resolving(name) do
        block = @blocks[name]
        next @read.call(name, @values) unless block

        @values[name] = @scope.instance_exec(&block)
      end
    end

    def resolving(name)
      if @resolving.include?(name)
        cycle = (@resolving + [name]).join(' -> ')
        raise FactoryBakery::Error, "Cyclic attribute dependency: #{cycle}"
      end

      @resolving.push(name)
      begin
        yield
      ensure
        @resolving.pop
      end
    end
  end
end
