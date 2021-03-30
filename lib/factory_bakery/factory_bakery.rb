module FactoryBakery
  class FactoryBakery
    self.class.attr_accessor :generator
    self.generator = FFakerGenerator.new

    attr_writer :generator

    def generator
      @generator || self.class.generator
    end

    def bake(model, custom_values = {}, &block)
      klass = model.is_a?(Class) ? model : model.class
      params = make_fake_params(klass.attribute_types)

      if model.is_a? Class
        puts params
        model.new(**params, **custom_values, &block)
      else
        model.assign_attributes(**params, **custom_values, **model.attributes)
      end
    end

    def bake!(model, custom_values = {}, &block)
      result = bake(model, custom_values, &block)
      result.save!
      yield result if block_given?
      result
    end

    def make_fake_params(attributes)
      attributes
        .reject { |key| key.to_s == 'id' }
        .map do |key, attr|
        [key.to_sym, generator.call(AttributeDescriptor.from_attribute(key.to_sym, attr))]
      end.to_h
    end
  end
end