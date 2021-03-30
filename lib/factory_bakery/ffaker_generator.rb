require 'ffaker'
require 'factory_bakery'
require_relative 'generator_registry'

module FactoryBakery
  class FFakerGenerator
    include GeneratorRegistry

    def call(attr_descriptor)
      registry[attr_descriptor.type].try(:call, attr_descriptor)
    end

    register(:integer) do |descriptor|
      choices_or_else(descriptor) do
        FFaker.rand(descriptor.limit).to_i
      end
    end
    register(:big_integer, &registry[:integer])

    register(:float) do |descriptor|
      choices_or_else(descriptor) do
        FFaker.rand(descriptor.limit).to_f
      end
    end
    register(:decimal, &registry[:decimal])

    register(:string) do |descriptor|
      choices_or_else(descriptor) do
        if descriptor.name.include? "email"
          FFaker::Internet.unique.email
        else
          FFaker::Lorem.characters(descriptor.limit || 255)
        end
      end
    end
    register(:immutable_string, &registry[:string])

    register(:datetime) do |descriptor|
      choices_or_else(descriptor) do
        FFaker::Time.datetime
      end
    end
    register(:time, &registry[:datetime])

    register(:date) do |descriptor|
      choices_or_else(descriptor) do
        FFaker::Time.datetime
      end
    end

    register(:boolean) do
      FFaker::Boolean.maybe
    end
  end
end