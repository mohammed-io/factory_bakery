module FactoryBakery
  class FactoryBakery
    def self.instance
      @instance ||= new
    end

    self.class.attr_accessor :first_generator
    self.class.attr_accessor :second_generator

    self.first_generator = FFakerGenerator.new
    attr_writer :first_generator, :second_generator
    def first_generator
      @first_generator || self.class.first_generator
    end

    def second_generator
      @second_generator || self.class.second_generator
    end

    def bake(model, custom_values = {}, &block)
      klass = model.is_a?(Class) ? model : model.class

      keys_to_skip = custom_values.keys.map(&:to_s)

      if model.is_a? Class
        model.new(
          **make_fake_params(klass.attribute_types.except(*keys_to_skip), first_generator),
          **make_fake_params(klass.attribute_types.except(*keys_to_skip), second_generator),
          **custom_values, &block
        )
      else
        model.assign_attributes(
          **make_fake_params(klass.attribute_types.except(*keys_to_skip), first_generator),
          **make_fake_params(klass.attribute_types.except(*keys_to_skip), second_generator),
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
      puts attributes.count
      attributes
        .reject { |key| key.to_s == 'id' }
        .map do |key, attr|
        [key.to_sym, generator.call(AttributeDescriptor.from_attribute(key.to_sym, attr))]
      end.to_h
    end
  end
end