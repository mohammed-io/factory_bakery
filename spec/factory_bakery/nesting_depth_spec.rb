# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'FactoryBakery nested-bake depth backstop' do
  # The backstop is a global setting, so every example that changes it restores
  # the previous value even when the assertion fails.
  def with_max_bake_depth(value)
    previous = FactoryBakery.max_bake_depth
    FactoryBakery.max_bake_depth = value
    yield
  ensure
    FactoryBakery.max_bake_depth = previous
  end

  # Defines :<prefix>_1 .. :<prefix>_<length>, all baking the same model. Every
  # level bakes the next one except the leaf, which ends the chain with nil.
  def define_bake_chain(model, length, prefix)
    (1..length).each do |level|
      FactoryBakery.define(:"#{prefix}_#{level}", klass: model) do
        parent { level < length ? FactoryBakery.bake(:"#{prefix}_#{level + 1}") : nil }
      end
    end
    :"#{prefix}_1"
  end

  describe 'runaway recursion' do
    it 'raises NestingTooDeepError naming the class path instead of SystemStackError' do
      account_model = define_model('BakeCycleAccount', name: :string, user_id: :integer) do
        belongs_to :user, class_name: 'BakeCycleUser', optional: true
      end
      user_model = define_model('BakeCycleUser', name: :string, account_id: :integer) do
        belongs_to :account, class_name: 'BakeCycleAccount', optional: true
      end

      FactoryBakery.define(user_model) do
        account { FactoryBakery.bake(account_model) }
      end
      FactoryBakery.define(account_model) do
        user { FactoryBakery.bake(user_model) }
      end

      expect { FactoryBakery.bake(user_model) }.to raise_error(FactoryBakery::NestingTooDeepError) { |error|
        expect(error).to be_a(FactoryBakery::Error)
        expect(error.message).to include('max_bake_depth (10)')
        expect(error.message).to include('BakeCycleUser -> BakeCycleAccount -> BakeCycleUser')
      }
    end

    it 'raises for a self-referential factory whose block bakes the same class' do
      node = define_class('BakeSelfNode') { attr_accessor :parent }

      FactoryBakery.define(node) do
        parent { FactoryBakery.bake(node) }
      end

      expect { FactoryBakery.bake(node) }.to raise_error(FactoryBakery::NestingTooDeepError) { |error|
        expect(error.message).to include('BakeSelfNode')
      }
    end
  end

  describe 'configurable depth limit' do
    it 'raises at bake time, not at definition time, when a chain is deeper than the limit' do
      node = define_class('BoundaryNode') { attr_accessor :parent }
      root = define_bake_chain(node, 3, 'boundary_chain')

      with_max_bake_depth(2) do
        expect { FactoryBakery.bake(root) }.to raise_error(FactoryBakery::NestingTooDeepError) do |error|
          expect(error.message).to include('max_bake_depth (2)')
        end
      end
    end

    it 'raises when a four-level chain exceeds a max depth of three' do
      node = define_class('DepthLimitNode') { attr_accessor :parent }
      root = define_bake_chain(node, 4, 'depth_limit_chain')

      with_max_bake_depth(3) do
        expect { FactoryBakery.bake(root) }.to raise_error(FactoryBakery::NestingTooDeepError) do |error|
          expect(error.message).to include('max_bake_depth (3)')
        end
      end
    end

    it 'allows a three-level chain when the max depth is three' do
      node = define_class('DepthOkNode') { attr_accessor :parent }
      root = define_bake_chain(node, 3, 'depth_ok_chain')

      with_max_bake_depth(3) do
        record = FactoryBakery.bake(root)

        expect(record).to be_a(node)
        expect(record.parent).to be_a(node)
        expect(record.parent.parent).to be_a(node)
        expect(record.parent.parent.parent).to be_nil
      end
    end
  end

  describe 'nesting that is allowed' do
    it 'permits finite same-class nesting ended by a leaf factory' do
      node = define_class('FiniteNode') { attr_accessor :parent }

      FactoryBakery.define(:finite_leaf, klass: node) { parent { nil } }
      FactoryBakery.define(:finite_child, klass: node) do
        parent { FactoryBakery.bake(:finite_leaf) }
      end

      record = FactoryBakery.bake(:finite_child)

      expect(record.parent).to be_a(node)
      expect(record.parent.parent).to be_nil
    end

    it 'leaves the public API unchanged for a non-nested bake' do
      model = define_model('PlainNestRecord', name: :string)

      record = FactoryBakery.bake(model, name: 'given')

      expect(record).to be_a(model)
      expect(record).to be_new_record
      expect(record.name).to eq('given')
    end
  end

  describe 'context lifecycle' do
    it 'starts from zero depth for an independent bake after an error mid-bake' do
      node = define_class('ResetNode') { attr_accessor :parent }

      FactoryBakery.define(node) do
        parent { FactoryBakery.bake(node) }
      end

      with_max_bake_depth(3) do
        expect { FactoryBakery.bake(node) }.to raise_error(FactoryBakery::NestingTooDeepError)

        # The same factory succeeds once its runaway block is suppressed by an
        # override, proving no stale depth leaked from the failed bake.
        record = FactoryBakery.bake(node, parent: nil)

        expect(record).to be_a(node)
        expect(record.parent).to be_nil
      end
    end

    it 'does not share build context between threads baking the same chain' do
      node = define_class('ThreadNode') { attr_accessor :parent }
      root = define_bake_chain(node, 4, 'thread_chain')

      failures = []
      with_max_bake_depth(4) do
        threads = 2.times.map do
          Thread.new do
            FactoryBakery.bake(root)
          rescue StandardError => e
            failures << e
          end
        end
        threads.each(&:join)
      end

      expect(failures).to be_empty
    end

    it 'does not share build context between fibers baking the same chain' do
      node = define_class('FiberNode') { attr_accessor :parent }
      root = define_bake_chain(node, 4, 'fiber_chain')

      failures = []
      with_max_bake_depth(4) do
        fibers = 2.times.map do
          Fiber.new do
            FactoryBakery.bake(root)
          rescue StandardError => e
            failures << e
          end
        end
        fibers.each(&:resume)
      end

      expect(failures).to be_empty
    end
  end
end
