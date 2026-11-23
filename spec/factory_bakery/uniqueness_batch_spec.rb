# frozen_string_literal: true

require 'spec_helper'
require 'active_support/notifications'

# The batched uniqueness check: when every unique column of a record is a
# plain case-sensitive unscoped uniqueness validator on a scalar column, the
# bake asks the database once for all of them, with every value a bind
# parameter. Anything else -- a scope, a case-folded validator, an inherited
# one, an index-only column, unprepared adapters -- falls back to the
# per-column probe and stays correct.
RSpec.describe 'batched uniqueness check' do
  include DefineConstantMacros

  def selects_in
    statements = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      statements << payload[:sql] if payload[:sql].start_with?('SELECT') && payload[:name] != 'SCHEMA'
    end
    yield
    statements
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  describe 'a model with two plain unique string columns' do
    let!(:model) do
      define_model('BatchPairCode', code: :string, token: :string) do
        validates :code, :token, uniqueness: true
      end
    end

    it 'issues exactly one SELECT for an unsaved bake' do
      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'beta')

      statements = selects_in { FactoryBakery.bake(model, fill_optional: true) }

      expect(statements.size).to eq(1)
    end

    it 'still issues one SELECT for three unique columns' do
      third = define_model('BatchTripleCode', code: :string, token: :string, slug: :string) do
        validates :code, :token, :slug, uniqueness: true
      end
      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'beta', 'gamma')

      statements = selects_in { FactoryBakery.bake(third, fill_optional: true) }

      expect(statements.size).to eq(1)
    end
  end

  describe 'a model with one plain unique column' do
    let!(:model) do
      define_model('BatchSingleCode', code: :string) do
        validates :code, uniqueness: true
      end
    end

    it 'issues exactly one SELECT, as the per-column check did' do
      allow(FFaker::Lorem).to receive(:word).and_return('alpha')

      statements = selects_in { FactoryBakery.bake(model, fill_optional: true) }

      expect(statements.size).to eq(1)
    end
  end

  describe 'a collision on one of two batched columns' do
    let!(:model) do
      define_model('BatchCollisionCode', code: :string, token: :string) do
        validates :code, :token, uniqueness: true
      end
    end

    it 'regenerates the collided column, leaves the other untouched and persists' do
      model.create!(code: 'alpha')
      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'beta', 'gamma')

      record = FactoryBakery.bake!(model, fill_optional: true)

      expect(record.code).to eq('gamma')
      expect(record.token).to eq('beta')
      expect(record).to be_persisted
      expect(model.count).to eq(2)
    end
  end

  describe 'a plain column beside a case_sensitive: false column' do
    let!(:model) do
      define_model('BatchMixedCode', code: :string, token: :string) do
        validates :code, uniqueness: true
        validates :token, uniqueness: { case_sensitive: false }
      end
    end

    it 'regenerates a matching row for each column and persists' do
      model.create!(code: 'alpha')
      model.create!(token: 'omega')
      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'omega', 'gamma', 'delta')

      record = FactoryBakery.bake!(model, fill_optional: true)

      expect(record.code).to eq('gamma')
      expect(record.token).to eq('delta')
      expect(record).to be_persisted
      expect(model.count).to eq(3)
    end

    it 'asks twice: one batch for the plain column, one per-column probe for the case-folded one' do
      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'omega')

      statements = selects_in { FactoryBakery.bake(model, fill_optional: true) }

      expect(statements.size).to eq(2)
    end
  end

  describe 'columns the batch cannot answer' do
    it 'still respects an existing row for a scope: validator' do
      scoped = define_model('BatchScopedCode', code: :string, account_id: :integer) do
        validates :code, uniqueness: { scope: :account_id }
      end
      scoped.create!(code: 'alpha', account_id: 1)
      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'beta')

      expect(FactoryBakery.bake(scoped, account_id: 1, fill_optional: true).code).to eq('beta')
    end

    it 'still respects an existing row for a unique-index-only column' do
      model = define_model('BatchIndexedCode', code: :string)
      model.connection.add_index(model.table_name, :code, unique: true)
      model.create!(code: 'alpha')
      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'beta')

      expect(FactoryBakery.bake(model, fill_optional: true).code).to eq('beta')
    end

    it 'still respects an existing row for an STI subclass with an inherited validator' do
      define_model('BatchStiBase', code: :string, type: :string) do
        validates :code, uniqueness: true
      end
      child = define_class('BatchStiChild', BatchStiBase)
      BatchStiBase.create!(code: 'alpha')
      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'beta')

      expect(FactoryBakery.bake(child, fill_optional: true).code).to eq('beta')
    end

    it 'batches a unique integer column with its typed value and respects an existing row' do
      model = define_model('BatchIntegerCode', code: :integer) do
        validates :code, uniqueness: true
      end
      allow(FactoryBakery::Randomness).to receive(:rand).and_return(42, 42, 43)

      first = FactoryBakery.bake!(model, fill_optional: true)
      second = FactoryBakery.bake!(model, fill_optional: true)

      expect(first.code).to eq(42)
      expect(second.code).to eq(43)
      expect(model.count).to eq(2)
    end
  end

  describe 'without prepared statements' do
    let!(:model) do
      define_model('BatchUnpreparedCode', code: :string, token: :string) do
        validates :code, :token, uniqueness: true
      end
    end

    it 'falls back to the per-column probe and stays correct' do
      allow(model.connection).to receive(:prepared_statements).and_return(false)
      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'beta')

      record = nil
      statements = selects_in { record = FactoryBakery.bake(model, fill_optional: true) }

      expect(statements.size).to eq(2)
      expect(record.code).to eq('alpha')
      expect(record.token).to eq('beta')
    end
  end

  describe 'values travel only as bind parameters' do
    let(:malicious) { "x'); DROP TABLE batch_accounts; --" }

    it 'stores an overridden value containing SQL literally and the table survives' do
      model = define_model('BatchOverrideAccount', code: :string, token: :string) do
        validates :code, :token, uniqueness: true
      end

      record = FactoryBakery.bake!(model, code: malicious, fill_optional: true)

      expect(model.find_by(code: malicious)).to eq(record)
      expect(model.count).to eq(1)
    end

    it 'binds a generated value containing SQL and the table survives' do
      model = define_model('BatchInjectionAccount', code: :string) do
        validates :code, uniqueness: true
      end
      model.create!(code: malicious)
      allow(FFaker::Lorem).to receive(:word).and_return(malicious, 'safe')

      record = FactoryBakery.bake!(model, fill_optional: true)

      expect(record.code).to eq('safe')
      expect(model.find_by(code: malicious)).to be_present
      expect(model.count).to eq(2)
    end
  end
end
