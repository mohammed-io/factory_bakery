# frozen_string_literal: true

require 'spec_helper'
require 'active_support/notifications'

# The uniqueness check asks the model's own validator against a probe copy of
# the record. These examples pin what that must keep doing: see rows the bake
# did not write, ask the database once per unique column, and still honour a
# validator the base class of an STI hierarchy declared.
RSpec.describe 'plain uniqueness check' do
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

  let!(:model) do
    define_model('PlainUnique', code: :string) do
      validates :code, uniqueness: true
    end
  end

  it 'regenerates a value a row already holds' do
    model.create!(code: 'alpha')
    allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'beta')

    expect(FactoryBakery.bake(model, fill_optional: true).code).to eq('beta')
  end

  it 'asks the database once per unique column and writes nothing' do
    statements = selects_in { FactoryBakery.bake(model) }

    expect(statements.size).to eq(1)
    expect(model.count).to eq(0)
  end

  it 'does not collide with its own saved row' do
    record = FactoryBakery.bake!(model)

    expect(FactoryBakery.bake(model).code).not_to eq(record.code)
  end

  context 'with an STI subclass of a class that declared the validator' do
    before do
      define_model('PlainUniqueBase', code: :string, type: :string) do
        validates :code, uniqueness: true
      end
      define_class('PlainUniqueChild', PlainUniqueBase)
    end

    it 'still treats a value held by a base-class row as taken' do
      PlainUniqueBase.create!(code: 'alpha')
      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'beta')

      expect(FactoryBakery.bake(PlainUniqueChild, fill_optional: true).code).to eq('beta')
    end
  end
end
