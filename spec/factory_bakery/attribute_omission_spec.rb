# frozen_string_literal: true

require 'spec_helper'
require 'factory_bakery/associations'

# Issue #52: `skip :attribute` in a definition or trait leaves the attribute
# unassigned. It is a declaration for precedence purposes: later traits and
# call-site overrides beat it, and it suppresses heuristics and plugin
# auto-build for the whole alias group.
RSpec.describe 'attribute omission with skip (issue #52)' do
  include DefineConstantMacros

  describe 'base definitions' do
    it 'leaves an omitted attribute at its default and never calls its setter' do
      model = define_model('SkipDefault',
                           avatar_url: { type: :string, default: '' },
                           other: :string) do
        validates :avatar_url, presence: true

        def avatar_url=(_value)
          raise 'avatar_url setter must not be called'
        end
      end

      FactoryBakery.define(model) { skip :avatar_url }

      record = FactoryBakery.bake(model)

      expect(record.avatar_url).to eq('')
    end

    it 'keeps non-blank defaults and accepts several names in one call' do
      model = define_model('SkipMany',
                           state: { type: :string, default: 'draft' },
                           token: { type: :string, default: 't-1' },
                           title: :string) do
        validates :title, presence: true
      end

      FactoryBakery.define(model) { skip :state, :token }

      record = FactoryBakery.bake(model)

      expect(record.state).to eq('draft')
      expect(record.token).to eq('t-1')
      expect(record.title).to be_present
    end

    it 'still omits the attribute under the fill_optional opt-in' do
      model = define_model('SkipFullMode',
                           skipped: { type: :string, default: 'default' },
                           filled: :string) do
        validates :filled, presence: true
      end

      FactoryBakery.define(model) { skip :skipped }

      record = FactoryBakery.bake(model, fill_optional: true)

      expect(record.skipped).to eq('default')
      expect(record.filled).to be_present
    end
  end

  describe 'precedence' do
    it 'lets a later trait declaration replace a base omission' do
      model = define_model('SkipThenTrait', name: { type: :string, default: 'default' })

      FactoryBakery.define(model) do
        skip :name

        trait :named do
          name { 'from trait' }
        end
      end

      expect(FactoryBakery.bake(model).name).to eq('default')
      expect(FactoryBakery.bake(model, :named).name).to eq('from trait')
    end

    it 'lets a later skip replace a base declaration without evaluating it' do
      model = define_model('TraitThenSkip', name: { type: :string, default: 'default' })

      FactoryBakery.define(model) do
        name { raise 'base declaration should not run' }

        trait :omitted do
          skip :name
        end
      end

      expect(FactoryBakery.bake(model, :omitted).name).to eq('default')
    end

    it 'lets a call-site override, including explicit nil, win and call the setter' do
      model = define_model('SkipOverride', name: { type: :string, default: 'default' }) do
        def self.calls
          @calls ||= []
        end

        def name=(value)
          self.class.calls << value
          super
        end
      end

      FactoryBakery.define(model) { skip :name }

      record = FactoryBakery.bake(model, name: 'override')
      expect(record.name).to eq('override')
      expect(model.calls).to include('override')

      model.calls.clear
      record = FactoryBakery.bake(model, name: nil)
      expect(record.name).to be_nil
      expect(model.calls).to include(nil)
    end
  end

  describe 'associations' do
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

    it 'suppresses auto-build of a required belongs_to parent and its FK' do
      parent = define_model('SkipOwner', name: :string)
      child = define_model('SkipOwned', account_id: :integer) do
        belongs_to :account, class_name: 'SkipOwner', optional: false
      end

      expect(FactoryBakery.bake(child).account).to be_a(parent)

      FactoryBakery.define(child) { skip :account }

      record = FactoryBakery.bake(child)
      expect(record.account).to be_nil
      expect(record.account_id).to be_nil
    end

    it 'omits the whole polymorphic alias group' do
      define_model('SkipCommentable', title: :string)
      model = define_model('SkipEvent', commentable_type: :string, commentable_id: :integer) do
        belongs_to :commentable, polymorphic: true, optional: false
      end

      expect { FactoryBakery.bake(model) }.to raise_error(FactoryBakery::Error)

      FactoryBakery.define(model) { skip :commentable }

      record = FactoryBakery.bake(model)
      expect(record.commentable).to be_nil
      expect(record.commentable_type).to be_nil
      expect(record.commentable_id).to be_nil
    end
  end

  describe 'an attribute literally named skip' do
    it 'can be declared with add_attribute' do
      model = define_model('SkipNamedColumn', skip: { type: :string, default: 'default' })

      FactoryBakery.define(model) { add_attribute(:skip) { 'declared' } }

      expect(FactoryBakery.bake(model).skip).to eq('declared')
    end

    it 'fails loudly when skip is given a value block' do
      model = define_model('SkipAsAttribute', skip: :string)

      FactoryBakery.define(model) { skip { 'value' } }

      expect { FactoryBakery.bake(model) }.to raise_error(FactoryBakery::Error, /add_attribute\(:skip\)/)
    end
  end
end
