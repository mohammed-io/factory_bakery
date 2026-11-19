# frozen_string_literal: true

require 'spec_helper'

# The verified fallback wraps an attempt in a savepoint only when the fallback
# can trigger. Rails opens transactions lazily, so the gate itself is not
# visible in SQL; these examples pin the behaviour on both sides of it.
RSpec.describe 'fallback savepoint gate' do
  include DefineConstantMacros

  it 'bakes a model whose validation is fully discoverable' do
    model = define_model('GatePlain', title: { type: :string, null: false }, note: :string) do
      validates :title, presence: true
    end

    record = FactoryBakery.bake(model)

    expect(record).to be_valid
    expect(record.note).to be_nil
  end

  it 'still falls back for a model whose custom validation needs an optional column' do
    model = define_model('GateFallback', title: { type: :string, null: false }, note: :string) do
      validate { errors.add(:note, :blank) if note.nil? }
    end

    expect(FactoryBakery.bake(model)).to be_valid
  end

  it 'still falls back when a validated column with a default is left at a blank default' do
    model = define_model('GateDefault', title: { type: :string, null: false },
                                        code: { type: :string, default: '' }) do
      validates :code, length: { minimum: 3 }, allow_nil: false
    end

    expect(FactoryBakery.bake(model)).to be_valid
  end
end
