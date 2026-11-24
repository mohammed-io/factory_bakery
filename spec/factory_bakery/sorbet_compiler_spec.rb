# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'the FactoryBakery Tapioca compiler' do
  let(:compiler) { Tapioca::Dsl::Compilers::FactoryBakery }

  before do
    begin
      require 'tapioca/internal'
    rescue LoadError
      skip 'Tapioca is unavailable. Add tapioca to the test bundle to run these specs.'
    end

    require 'tapioca/dsl/compilers/factory_bakery'
  end

  it 'generates the fallback recipe entry point when opted in without model definitions' do
    stub_const('FactoryBakery::Sorbet', Module.new)
    stub_registry({})

    expect(compiler.gather_constants).to eq([FactoryBakery])
    expect(generated_rbi).to include('target: T::Class[T.type_parameter(:Model)]', 'target: ::Symbol')
    hide_const('FactoryBakery::Sorbet')
    expect(compiler.gather_constants).to be_empty
  end

  it 'generates typed overrides and trait methods only for the recipes that support them' do
    user = define_model('SorbetCompilerUser', name: :string, score: :integer, metadata: :json)
    group = define_model('SorbetCompilerGroup', label: :string)
    user.belongs_to :group, class_name: group.name
    group.has_many :users, class_name: user.name, foreign_key: :group_id
    define_model('SorbetCompilerUnregistered', label: :string)
    stub_registry({})

    FactoryBakery.define(user) do
      trait(:admin) {}
      trait(:verified) {}
      trait(:target) {}
    end
    FactoryBakery.define(:compiler_special, klass: group) { trait(:symbol_only) {} }
    FactoryBakery.define(Class.new { include ActiveModel::Model }) { trait(:ignored) {} }

    rbi = generated_rbi

    expect(rbi).to include(
      'class ForSorbetCompilerUser < ::FactoryBakery::Recipe',
      'Model = type_member { { fixed: ::SorbetCompilerUser } }',
      'def admin; end',
      'def verified; end',
      'name: T.nilable(::String)',
      'score: T.nilable(::Integer)',
      'metadata: T.untyped',
      'group: T.nilable(::SorbetCompilerGroup)',
      'users: T.nilable(T::Array[::SorbetCompilerUser])',
      'fill_optional: T.untyped',
      'validate: T.untyped',
      'blk: T.nilable(T.proc.params(record: ::SorbetCompilerUser).void)',
      'def bake(',
      'def bake!(',
      'name: nil',
      'validate: nil',
      'target: T.class_of(::SorbetCompilerUser)',
      'target: T.class_of(::SorbetCompilerGroup)',
      'target: T::Class[T.type_parameter(:Model)]',
      'target: ::Symbol',
      'def self.recipe(target, *args); end'
    )
    expect(rbi).not_to include('def symbol_only', 'def ignored', 'def target', 'SorbetCompilerUnregistered')
    expect(rbi.index('target: T.class_of(::SorbetCompilerUser)')).to be < rbi.index('target: T::Class[')
  end

  def stub_registry(definitions)
    allow(FactoryBakery::BakeryBuilder).to receive(:definitions).and_return(definitions)
  end

  def generated_rbi
    tree = RBI::Tree.new
    pipeline = Tapioca::Dsl::Pipeline.new(requested_constants: [FactoryBakery], requested_compilers: [compiler])
    compiler.new(pipeline, tree, FactoryBakery).decorate
    tree.string
  end
end
