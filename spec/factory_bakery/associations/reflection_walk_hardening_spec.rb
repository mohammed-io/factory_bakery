# frozen_string_literal: true

require 'spec_helper'
require 'factory_bakery/associations'

# W6: a partially-loaded model (its constant exists, but one reflection cannot
# be resolved) must not crash reflection walks. Broken edges are dropped from
# introspection and recorded; an explicit reference still gets a clear error.
# Every assertion goes through define/bake/bake! and the mapper's public
# introspection answer -- never through builder internals.
RSpec.describe 'FactoryBakery associations reflection-walk hardening' do
  before do
    FactoryBakery.reset_plugins!
    FactoryBakery.register_plugin(FactoryBakery::Associations::Plugin)
    FactoryBakery::Associations.reset_configuration!
    FactoryBakery::Associations.mode = :required_only
  end

  after do
    FactoryBakery.reset_plugins!
    FactoryBakery::Associations.reset_configuration!
  end

  def define_partially_loaded_owner(name)
    define_model(name, name: :string) do
      has_one :ghost, class_name: 'W6HardeningMissingGhost', inverse_of: :owner
    end
  end

  describe 'baking a partially-loaded class' do
    it 'persists an owner with an unresolved optional belongs_to in all mode' do
      owner_model = define_model('HardeningOptionalOwner', ghost_id: :integer) do
        belongs_to :ghost, class_name: 'HardeningMissingGhost', optional: true
      end
      FactoryBakery::Associations.mode = :all

      owner = FactoryBakery.bake!(owner_model)

      expect(owner.reload.ghost_id).to be_nil
    end

    it 'reports an unresolved belongs_to backed by a non-null foreign key' do
      owner_model = define_model('HardeningRequiredOwner', ghost_id: { type: :integer, null: false }) do
        belongs_to :ghost, class_name: 'HardeningMissingGhost', optional: true
      end

      expect { FactoryBakery.bake!(owner_model) }
        .to raise_error(FactoryBakery::Error, /ghost.*could not be resolved/)
    end

    it 'succeeds when the broken edge is never referenced' do
      owner_model = define_partially_loaded_owner('W6HardeningOwner')

      expect { FactoryBakery.bake(owner_model) }.not_to raise_error
    end

    it 'records the skipped edge for diagnostics while intact siblings still bake' do
      define_model('W6HardeningAccount', name: :string)
      owner_model = define_model('W6HardeningSiblingOwner', name: :string, account_id: :integer) do
        belongs_to :account, class_name: 'W6HardeningAccount', optional: false
        has_one :ghost, class_name: 'W6HardeningMissingGhost', inverse_of: :owner
      end

      introspection = FactoryBakery::MapperRegistry.association_introspection(owner_model)
      expect(introspection.map(&:name)).to eq(['account'])
      expect(introspection.failure_for(:ghost)).to include('NameError')

      owner = FactoryBakery.bake(owner_model)
      expect(owner.account).to be_a(W6HardeningAccount)
    end

    it 'answers an empty introspection, not nil, when every reflection is broken' do
      owner_model = define_partially_loaded_owner('W6HardeningOnlyBroken')

      introspection = FactoryBakery::MapperRegistry.association_introspection(owner_model)
      expect(introspection).not_to be_nil
      expect(introspection).to be_empty

      expect { FactoryBakery.bake(owner_model) }.not_to raise_error
    end
  end

  describe 'explicit references to a broken edge' do
    it 'raises a contextual error naming the edge that could not be introspected' do
      owner_model = define_partially_loaded_owner('W6HardeningDeclaredOwner')
      FactoryBakery.define(owner_model) { association :ghost }

      expect { FactoryBakery.bake(owner_model) }
        .to raise_error(FactoryBakery::Error, /ghost.*could not be introspected/)
    end

    it 'raises a contextual error, not a raw NameError, when the target cannot resolve' do
      post_model = define_model('W6HardeningLazyPost', name: :string, ghost_id: :integer) do
        belongs_to :ghost, class_name: 'W6HardeningMissingLazyClass', optional: true
      end
      FactoryBakery.define(post_model) { association :ghost }

      expect { FactoryBakery.bake(post_model) }
        .to raise_error(FactoryBakery::Error, /ghost.*could not be resolved/)
    end
  end

  describe 'back-edge walking' do
    it 'keeps an intact back edge when a sibling candidate is broken' do
      define_model('W6HardeningAuthor', name: :string)
      post_model = define_model('W6HardeningPost', title: :string, author_id: :integer) do
        belongs_to :author, class_name: 'W6HardeningAuthor', optional: true
      end
      author_model = W6HardeningAuthor
      author_model.has_many :posts,
                            class_name: 'W6HardeningPost',
                            foreign_key: :author_id,
                            inverse_of: :author
      author_model.has_many :ghosts, class_name: 'W6HardeningMissingGhost', inverse_of: :author
      FactoryBakery::Associations.mode = :all

      post = FactoryBakery.bake!(post_model)

      expect(post.author).to be_a(author_model)
      expect(post_model.count).to eq(1)
    end
  end
end
