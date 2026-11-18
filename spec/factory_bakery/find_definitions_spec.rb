# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'fileutils'

RSpec.describe 'FactoryBakery definition file loading' do
  around do |example|
    Dir.mktmpdir('factory_bakery-definitions-') do |directory|
      @definition_root = directory

      begin
        example.run
      ensure
        FactoryBakery.definition_paths = []
      end
    end
  end

  def write_definition(relative_path, source)
    path = File.join(@definition_root, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, source)
  end

  def definition_path(directory)
    File.join(@definition_root, directory)
  end

  it 'has no definition paths configured by default' do
    expect(FactoryBakery.definition_paths).to be_empty
  end

  it 'bakes definitions declared in a real file on disk' do
    model = define_model('LoadedFromDisk', label: :string) do
      validates :label, presence: true
    end

    write_definition(
      'factories/loaded_from_disk.rb',
      "FactoryBakery.define(LoadedFromDisk) { label { 'from definition file' } }\n"
    )

    FactoryBakery.definition_paths = [definition_path('factories')]
    FactoryBakery.find_definitions

    expect(FactoryBakery.bake(model).label).to eq('from definition file')
  end

  it 'loads definition files in nested directories recursively' do
    model = define_model('NestedFromDisk', label: :string) do
      validates :label, presence: true
    end

    write_definition(
      'factories/deeply/nested/nested_from_disk.rb',
      "FactoryBakery.define(NestedFromDisk) { label { 'nested definition' } }\n"
    )

    FactoryBakery.definition_paths = [definition_path('factories')]
    FactoryBakery.find_definitions

    expect(FactoryBakery.bake(model).label).to eq('nested definition')
  end

  it 'accepts a single string instead of an array of definition paths' do
    model = define_model('StringPathModel', name: :string)

    write_definition(
      'single_path/string_path_model.rb',
      "FactoryBakery.define(StringPathModel) { name { 'single string path' } }\n"
    )

    FactoryBakery.definition_paths = definition_path('single_path')
    FactoryBakery.find_definitions

    expect(FactoryBakery.bake(model).name).to eq('single string path')
  end

  it 'skips nonexistent definition paths without raising' do
    FactoryBakery.definition_paths = [definition_path('does_not_exist')]

    expect { FactoryBakery.find_definitions }.not_to raise_error
  end

  it 'can load definitions twice in one process and still resolve them' do
    model = define_model('ReloadedFromDisk', name: :string)

    write_definition(
      'reload/reloaded_from_disk.rb',
      "FactoryBakery.define(ReloadedFromDisk) { name { 'reloaded' } }\n"
    )

    FactoryBakery.definition_paths = [definition_path('reload')]
    FactoryBakery.find_definitions

    expect { FactoryBakery.find_definitions }.not_to raise_error
    expect(FactoryBakery.bake(model).name).to eq('reloaded')
  end

  it 're-evaluates definition files so a second load refreshes the registration' do
    model = define_model('ReloadEvaluatedModel', name: :string)
    stub_const('DefinitionLoadCounter', Class.new do
      def self.next
        @count = count + 1
      end

      def self.count
        @count || 0
      end
    end)

    write_definition(
      'reevaluate/reload_evaluated_model.rb',
      <<~RUBY
        value = "load \#{DefinitionLoadCounter.next}"
        FactoryBakery.define(ReloadEvaluatedModel) { name { value } }
      RUBY
    )

    FactoryBakery.definition_paths = [definition_path('reevaluate')]

    FactoryBakery.find_definitions
    expect(FactoryBakery.bake(model).name).to eq('load 1')

    FactoryBakery.find_definitions
    expect(FactoryBakery.bake(model).name).to eq('load 2')
  end

  it 'surfaces a definition file error after loading files from earlier paths' do
    model = define_model('LoadedBeforeError', name: :string)

    write_definition(
      'first/loaded_before_error.rb',
      "FactoryBakery.define(LoadedBeforeError) { name { 'loaded first' } }\n"
    )
    write_definition('second/exploding.rb', "raise 'definition exploded'\n")

    FactoryBakery.definition_paths = [definition_path('first'), definition_path('second')]

    expect { FactoryBakery.find_definitions }
      .to raise_error(RuntimeError, 'definition exploded')
    expect(FactoryBakery.bake(model).name).to eq('loaded first')
  end
end
