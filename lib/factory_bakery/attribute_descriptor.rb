module FactoryBakery
  AttributeDescriptor = Struct.new(:name, :type, :limit, :range, :choices, :unique) do
    def self.from_attribute(key, attr)
      new(
        key.to_s,
        attr.type,
        attr.limit,
        attr.instance_variable_defined?(:@range) ? attr.instance_variable_get(:@range) : nil,
        attr.instance_variable_defined?(:@mapping) ? attr.instance_variable_get(:@mapping).values : nil
      )
    end
  end
end