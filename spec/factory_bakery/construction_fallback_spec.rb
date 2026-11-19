# frozen_string_literal: true

require 'spec_helper'

# Issue #56: some models cannot be instantiated with `new` -- a `default_scope`
# that raises while Rails applies its create attributes, or an
# `after_initialize` callback that raises. Baking retries with narrower
# construction strategies, in order: `unscoped { new }` (keeps
# after_initialize defaults) and callback-free construction (drops them).
RSpec.describe 'construction fallback for models whose new raises (issue #56)' do
  include DefineConstantMacros

  describe 'a default_scope that raises in new' do
    it 'bakes a populated record and keeps after_initialize defaults' do
      model = define_model('ScopeRaisingRecord', name: :string, plugin_name: :string) do
        default_scope { raise 'this scope is not available' }
        after_initialize { self.plugin_name ||= 'plugin-default' }
        validates :name, presence: true
      end

      expect { model.new }.to raise_error(RuntimeError, /this scope is not available/)

      record = FactoryBakery.bake(model)

      expect(record).to be_a(model)
      expect(record.name).to be_present
      expect(record.plugin_name).to eq('plugin-default')
    end

    it 'still applies initialize_with, declarations and call-site overrides' do
      model = define_model('ScopeRaisingLayers', name: :string, token: :string, label: :string) do
        default_scope { raise 'this scope is not available' }
        validates :name, presence: true
      end

      FactoryBakery.define(model) do
        initialize_with(token: 'seeded-token')
        label { 'declared-label' }
      end

      record = FactoryBakery.bake(model, label: 'overridden-label')

      expect(record.token).to eq('seeded-token')
      expect(record.label).to eq('overridden-label')
      expect(record.name).to be_present
    end

    it 'runs uniqueness probing without hitting the raising default scope' do
      model = define_model('ScopeRaisingUnique', code: :string) do
        default_scope { raise 'this scope is not available' }
        validates :code, presence: true, uniqueness: true, inclusion: { in: %w[only-value] }
      end

      FactoryBakery.bake!(model)

      # The probe reached the database and found the value taken; a probe that
      # ran under the raising default scope would surface its error instead.
      expect { FactoryBakery.bake(model) }
        .to raise_error(FactoryBakery::Error, /could not generate a unique value/)
    end
  end

  describe 'an after_initialize that raises' do
    it "bakes a populated record on Rails #{ActiveRecord::VERSION::STRING}" do
      model = define_model('InitializeRaisingRecord', name: :string) do
        after_initialize { raise 'initialize is not allowed' }
        validates :name, presence: true
      end

      expect { model.new }.to raise_error(RuntimeError, /initialize is not allowed/)

      record = FactoryBakery.bake(model)

      expect(record).to be_a(model)
      expect(record.name).to be_present
    end

    it 'persists the record with bake!' do
      model = define_model('InitializeRaisingSaved', name: :string) do
        after_initialize { raise 'initialize is not allowed' }
        validates :name, presence: true
      end

      record = FactoryBakery.bake!(model)

      expect(record).to be_persisted
      # Loading a row runs after_initialize too, so read it without instantiating.
      expect(model.pluck(:name)).to eq([record.name])
    end

    it 'applies initialize_with values to the record built without the constructor' do
      model = define_model('InitializeRaisingWithValues', name: :string, token: :string) do
        after_initialize { raise 'initialize is not allowed' }
        validates :name, presence: true
      end

      FactoryBakery.define(model) { initialize_with(token: 'seeded-token') }

      record = FactoryBakery.bake(model)

      expect(record.token).to eq('seeded-token')
      expect(record.name).to be_present
    end

    it 'still probes uniqueness on a record built without the constructor' do
      model = define_model('InitializeRaisingUnique', code: :string) do
        after_initialize { raise 'initialize is not allowed' }
        validates :code, presence: true, uniqueness: true
      end

      first = FactoryBakery.bake!(model)
      second = FactoryBakery.bake(model)

      expect(second.code).to be_present
      expect(second.code).not_to eq(first.code)
    end
  end

  describe 'a model every construction strategy fails on' do
    it 'surfaces the original exception class and message with a note' do
      model = define_model('UnconstructableRecord', name: :string) do
        default_scope { raise 'this scope is not available' }
        after_initialize { raise 'initialize is not allowed' }

        def self._default_attributes
          raise 'attributes are not available'
        end
      end

      expect { FactoryBakery.bake(model) }.to raise_error(
        RuntimeError,
        /\Aattributes are not available \(FactoryBakery also tried unscoped and callback-free construction\)\z/
      )
    end
  end

  describe 'a target without the framework internals' do
    it 'skips callback-free construction and surfaces the original error' do
      plain = define_class('ScopedPlainTarget') do
        include ActiveModel::Validations

        attr_accessor :name

        validates :name, presence: true

        def self.unscoped
          yield
        end

        def initialize(_attributes = nil)
          raise 'plain constructor boom'
        end
      end

      expect { FactoryBakery.bake(plain) }.to raise_error(
        RuntimeError,
        /\Aplain constructor boom \(FactoryBakery also tried unscoped construction\)\z/
      )
    end
  end

  describe 'ordinary models' do
    it 'calls new exactly once' do
      model = define_model('OrdinaryConstructedRecord', name: :string) do
        validates :name, presence: true

        class << self
          attr_accessor :new_calls
        end

        def self.new(*, **, &)
          self.new_calls = new_calls.to_i + 1
          super
        end
      end

      FactoryBakery.bake(model)

      expect(model.new_calls).to eq(1)
    end
  end

  describe 'plain objects' do
    it 'keeps the original error when no framework fallback applies' do
      plain = define_class('PlainRaisingTarget') do
        include ActiveModel::Validations

        attr_accessor :name

        validates :name, presence: true

        def initialize(_attributes = nil)
          raise 'plain constructor boom'
        end
      end

      expect { FactoryBakery.bake(plain) }.to raise_error(RuntimeError, 'plain constructor boom')
    end
  end
end
