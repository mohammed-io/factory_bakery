# frozen_string_literal: true

require 'spec_helper'
require 'active_model'

RSpec.describe 'lazy proc :in inclusion/exclusion sets (issue #36)' do
  include DefineConstantMacros

  describe 'proc inclusion sets (audit probe 10)' do
    let!(:model) do
      define_model('ProcInclusionTier', tier: :string) do
        validates :tier, inclusion: { in: ->(_record) { %w[basic pro] } }
      end
    end

    it 'bakes a value from the proc-returned set and validates' do
      records = 20.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:tier)).to all(satisfy { |value| %w[basic pro].include?(value) })
      expect(records).to all(be_valid)
    end

    it 'does not call the proc when the filler is initialized' do
      calls = 0
      lazy_model = define_model('LazyInitTier', tier: :string) do
        validates :tier, inclusion: {
          in: lambda { |_record|
            calls += 1
            %w[basic pro]
          }
        }
      end

      filler = FactoryBakery::AttributeFillers::StringFiller.new(lazy_model, :tier)

      expect(calls).to eq(0)
      filler.call
      expect(calls).to eq(1)
      filler.call
      expect(calls).to eq(2)
    end

    it 'evaluates the proc freshly for each bake, against the object being built' do
      calls = []
      fresh_model = define_model('FreshTier', tier: :string) do
        validates :tier, inclusion: {
          in: lambda { |record|
            calls << record
            %w[basic pro]
          }
        }
      end

      first = FactoryBakery.bake(fresh_model)
      second = FactoryBakery.bake(fresh_model)

      expect(calls.length).to eq(2)
      expect(calls).to all(be_a(fresh_model))
      expect(calls.first.object_id).not_to eq(calls.second.object_id)
      expect(%w[basic pro]).to include(first.tier, second.tier)
    end
  end

  describe 'proc exclusion sets' do
    it 'avoids values returned by the proc' do
      model = define_model('ProcExclusionCode', code: :string) do
        validates :code, exclusion: { in: ->(_record) { %w[basic] } }
      end
      allow(FFaker::Lorem).to receive(:word).and_return('basic', 'pro')

      record = FactoryBakery.bake(model)

      expect(record.code).to eq('pro')
      expect(record).to be_valid
    end

    it 'does not call the exclusion proc during filler initialization' do
      calls = 0
      model = define_model('LazyExclusionCode', code: :string) do
        validates :code, exclusion: {
          in: lambda { |_record|
            calls += 1
            %w[basic]
          }
        }
      end

      allow(FFaker::Lorem).to receive(:word).and_return('pro')

      FactoryBakery::AttributeFillers::StringFiller.new(model, :code)
      expect(calls).to eq(0)

      FactoryBakery.bake(model)
      expect(calls).to eq(1)
    end
  end

  describe 'procs that raise' do
    it 'wraps a raising inclusion proc in a contextual FactoryBakery::Error' do
      model = define_model('ProcRaiseTier', tier: :string) do
        validates :tier, inclusion: { in: ->(_record) { MissingTierNamespace::VALUES } }
      end

      expect { FactoryBakery.bake(model) }
        .to raise_error(FactoryBakery::Error, /ProcRaiseTier#tier.*inclusion.*MissingTierNamespace/m) { |error|
          expect(error.cause).to be_a(NameError)
        }
    end

    it 'wraps a raising exclusion proc in a contextual FactoryBakery::Error' do
      model = define_model('ProcRaiseExclusion', code: :string) do
        validates :code, exclusion: { in: ->(_record) { MissingExclusionNamespace::VALUES } }
      end

      expect { FactoryBakery.bake(model) }
        .to raise_error(FactoryBakery::Error, /ProcRaiseExclusion#code.*exclusion.*MissingExclusionNamespace/m)
    end
  end

  describe 'literal sets stay on the unchanged fast path' do
    it 'keeps literal array inclusion working' do
      model = define_model('LiteralArrayTier', tier: :string) do
        validates :tier, inclusion: { in: %w[basic pro] }
      end

      records = 20.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:tier)).to all(satisfy { |value| %w[basic pro].include?(value) })
      expect(records).to all(be_valid)
    end

    it 'keeps literal range inclusion working' do
      model = define_model('LiteralRangeCount', count: :integer) do
        validates :count, inclusion: { in: 3..7 }
      end

      records = 20.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:count)).to all(be_between(3, 7).inclusive)
      expect(records).to all(be_valid)
    end
  end

  describe 'proc sets across filler types' do
    it 'accepts a zero-arity proc' do
      model = define_model('ZeroArityTier', tier: :string) do
        validates :tier, inclusion: { in: -> { %w[basic pro] } }
      end

      records = 5.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:tier)).to all(satisfy { |value| %w[basic pro].include?(value) })
      expect(records).to all(be_valid)
    end

    it 'honors a proc set on an integer column' do
      model = define_model('ProcIntCount', count: :integer) do
        validates :count, inclusion: { in: ->(_record) { [3, 5, 7] } }
      end

      records = 20.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:count)).to all(satisfy { |value| [3, 5, 7].include?(value) })
      expect(records).to all(be_valid)
    end

    it 'honors a proc set on a date column' do
      dates = [Date.new(2020, 1, 1), Date.new(2021, 1, 1)]
      model = define_model('ProcDateEvent', event_on: :date) do
        validates :event_on, inclusion: { in: ->(_record) { dates } }
      end

      records = 10.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:event_on)).to all(satisfy { |value| dates.include?(value) })
      expect(records).to all(be_valid)
    end

    it 'honors a proc set on a boolean column' do
      model = define_model('ProcBoolFlag', flag: :boolean) do
        validates :flag, inclusion: { in: ->(_record) { [true] } }
      end

      records = 10.times.map { FactoryBakery.bake(model) }

      expect(records.map(&:flag)).to all(eq(true))
      expect(records).to all(be_valid)
    end
  end

  describe 'PORO routing' do
    it 'honors a proc inclusion set on an ActiveModel-compatible target' do
      base = Class.new do
        include ActiveModel::Model
        include ActiveModel::Validations
      end
      model = define_class('ProcTierPoro', base) do
        attr_accessor :tier

        validates :tier, inclusion: { in: ->(_record) { %w[basic pro] } }
      end

      record = FactoryBakery.bake(model)

      expect(%w[basic pro]).to include(record.tier)
      expect(record).to be_valid
    end
  end
end
