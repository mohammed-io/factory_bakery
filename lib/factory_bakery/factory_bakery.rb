module FactoryBakery
  class FactoryBakery
    def self.instance
      @instance ||= new
    end

    self.class.attr_accessor :generators

    self.generators = [FFakerGenerator.new]

    attr_writer :generators

    def generators
      @generators || self.class.generators
    end

    def bake(model, custom_values = {}, &block)
      klass = model.is_a?(Class) ? model : model.class

      keys_to_skip = custom_values.keys.map(&:to_s)

      params_from_generators = generators.map do |generator|
        make_fake_params(klass.attribute_types.except(*keys_to_skip), generator)
      end.reduce({}) do |result, hash|
        hash.merge(result)
      end

      if model.is_a? Class
        model.new(
          **params_from_generators,
          **custom_values, &block
        )
      else
        model.assign_attributes(
          **params_from_generators,
          **custom_values,
          **model.attributes
        )
        model
      end
    end

    def bake!(model, custom_values = {}, &block)
      result = bake(model, custom_values, &block)
      result.save!
      yield result if block_given?
      result
    end

    def make_fake_params(attributes, generator)
      return {} unless generator

      attributes
        .reject { |key| key.to_s == 'id' }
        .map do |key, attr|
        [key.to_sym, generator.call(AttributeDescriptor.from_attribute(key.to_sym, attr))]
      end.to_h
    end
  end
end