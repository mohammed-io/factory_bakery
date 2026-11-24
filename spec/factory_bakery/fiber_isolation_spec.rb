# frozen_string_literal: true

require 'spec_helper'

# A fiber or thread started inside a bake is an independent unit of work: it
# neither joins the bake that started it nor keeps that bake's state after the
# bake has finished.
RSpec.describe 'fiber isolation of build state' do
  let!(:widget) do
    define_model('IsolationWidget', name: :string, label: :string) do
      validates :name, presence: true
    end
  end

  after { FactoryBakery.fill_optional = false }

  it 'does not make a fiber baking inside a bake! part of the parent graph' do
    stray = nil
    other = define_model('IsolationOther', name: :string)
    FactoryBakery.define(widget) do
      name do
        stray = Fiber.new { FactoryBakery.bake(other) }.resume
        'parent'
      end
    end

    record = FactoryBakery.bake!(widget)

    expect(record).to be_persisted
    expect(stray).not_to be_persisted
  end

  it 'starts a fiber resumed after the bake ended from a clean context' do
    fiber = nil
    FactoryBakery.bake(widget) do
      fiber = Fiber.new do
        Fiber.yield
        [FactoryBakery::BuildContext.current.depth, FactoryBakery::FillOptional.current,
         FactoryBakery::BuildContext.current_record]
      end
      fiber.resume
    end

    expect(fiber.resume).to eq([0, false, nil])
  end

  it 'does not give a child fiber the fill_optional option of the bake that started it' do
    seen = nil
    FactoryBakery.define(widget) do
      name do
        seen = Fiber.new { FactoryBakery::FillOptional.current }.resume
        'x'
      end
    end

    FactoryBakery.bake(widget, fill_optional: true)

    expect(seen).to be(false)
  end

  it 'gives a child fiber the global validate setting, not the parent override' do
    seen = nil
    FactoryBakery.define(widget) do
      name do
        seen = Fiber.new { FactoryBakery::Verification.override }.resume
        'x'
      end
    end

    FactoryBakery.bake(widget, validate: false)

    expect(seen).to be_nil
  end

  it 'keeps the override of a nested bake on the same fiber' do
    seen = nil
    inner = define_model('IsolationInner', name: :string)
    FactoryBakery.define(widget) { name { FactoryBakery.bake(inner).name || 'x' } }
    FactoryBakery.define(inner) { name { seen = FactoryBakery::Verification.override } }

    FactoryBakery.bake(widget, validate: false)

    expect(seen).to be(false)
  end
end
