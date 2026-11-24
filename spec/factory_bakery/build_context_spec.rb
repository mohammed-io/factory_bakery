# frozen_string_literal: true

require 'spec_helper'

RSpec.describe FactoryBakery::BuildContext do
  let(:parent_class) { Class.new }
  let(:child_class) { Class.new }

  it 'exposes the class path of nested pushes in order and restores the outer context on pop' do
    described_class.push(parent_class) do
      described_class.push(child_class) do
        expect(described_class.current.path).to eq([parent_class, child_class])
        expect(described_class.current.depth).to eq(2)
      end

      expect(described_class.current.path).to eq([parent_class])
      expect(described_class.current.depth).to eq(1)
    end

    expect(described_class.current.path).to eq([])
    expect(described_class.current.depth).to eq(0)
  end

  it 'does not let a child fiber change the parent path or the parent unique-value registry' do
    key = [:widgets, :email, 'a@b']

    described_class.push(parent_class) do
      parent_context = described_class.current
      child_path = Fiber.new do
        inner_path = nil
        described_class.push(child_class) do
          inner_path = described_class.current.path
          described_class.record_unique_value(key)
        end
        inner_path
      end.resume

      # A fiber is an independent unit of work: its path starts from nothing.
      expect(child_path).to eq([child_class])
      expect(parent_context.path).to eq([parent_class])
      expect(described_class.current.path).to eq([parent_class])
      expect(described_class.unique_value_taken?(key)).to be(false)
    end
  end

  it 'sees a recorded unique value and restores a snapshot taken before it' do
    taken = [:widgets, :email, 'a@b']
    other = [:widgets, :email, 'c@d']

    described_class.push(parent_class) do
      described_class.record_unique_value(taken)
      expect(described_class.unique_value_taken?(taken)).to be(true)
      expect(described_class.unique_value_taken?(other)).to be(false)

      snapshot = described_class.unique_values
      described_class.record_unique_value(other)
      expect(described_class.unique_value_taken?(other)).to be(true)

      described_class.restore_unique_values(snapshot)
      expect(described_class.unique_value_taken?(taken)).to be(true)
      expect(described_class.unique_value_taken?(other)).to be(false)
    end
  end
end
