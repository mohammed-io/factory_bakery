# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'fileutils'

RSpec.describe 'FactoryBakery Rails generators' do
  around do |example|
    Dir.mktmpdir do |root|
      @root = root
      example.run
    end
  end

  def write(relative_path, contents)
    path = File.join(@root, relative_path)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, contents)
  end

  def generate(*args, config: '', before_boot: '')
    write('config/database.yml', "development:\n  adapter: sqlite3\n  database: ':memory:'\n")
    script = <<~RUBY
      require 'rails'
      require 'active_record/railtie'
      require 'action_controller/railtie'
      require 'action_view/railtie'
      require 'rails/test_unit/railtie'
      require 'factory_bakery'
      #{before_boot}
      class GeneratorApp < Rails::Application
        config.root = Dir.pwd
        config.eager_load = false
        config.secret_key_base = 'x' * 64
        #{config}
      end
      GeneratorApp.initialize!
      GeneratorApp.load_generators
      Rails::Generators.invoke(ARGV.shift, ARGV, destination_root: Dir.pwd)
    RUBY
    output, status = Open3.capture2e(RbConfig.ruby, '-e', script, '--', *args, chdir: @root)
    expect(status).to be_success, output
    output
  end

  def contents(path)
    File.read(File.join(@root, path))
  end

  def exists?(path)
    File.exist?(File.join(@root, path))
  end

  it 'generates a namespaced definition through the model hook' do
    output = generate('model', 'Admin::Post', 'title:string', 'user:references', 'subject:references{polymorphic}')

    expect(exists?('test/factories/admin/post.rb')).to be(true), output

    expect(contents('test/factories/admin/post.rb')).to include(
      'FactoryBakery.define(Admin::Post) do',
      '# title {',
      '# user { FactoryBakery.bake(User) }',
      '# subject { FactoryBakery.bake(SomeModel) }'
    )
  end

  it 'generates a definition through the scaffold hook' do
    generate('scaffold', 'Post', 'title:string')

    expect(contents('test/factories/post.rb')).to include('FactoryBakery.define(Post) do')
  end

  it 'skips the model hook on request' do
    generate('model', 'Post', '--skip-factory-bakery')

    expect(exists?('test/factories/post.rb')).to be(false)
  end

  it 'skips the scaffold hook on request' do
    generate('scaffold', 'Post', '--skip-factory-bakery')

    expect(exists?('app/models/post.rb')).to be(true)
    expect(exists?('test/factories/post.rb')).to be(false)
  end

  it 'honors the global disable setting' do
    generate('model', 'Post', config: 'config.factory_bakery.generators = false')

    expect(exists?('test/factories/post.rb')).to be(false)
    expect(exists?('test/fixtures/posts.yml')).to be(true)
  end

  it 'preserves an explicitly selected replacement unless FactoryBakery is opted in' do
    write('lib/generators/other/model/model_generator.rb', <<~RUBY)
      module Other
        class ModelGenerator < Rails::Generators::NamedBase
          argument :attributes, type: :array, default: []
          def write_marker
            create_file 'other.txt', name
          end
        end
      end
    RUBY
    config = 'config.generators.fixture_replacement :other'
    generate('model', 'Post', config: config)
    expect(contents('other.txt')).to eq('Post')
    expect(exists?('test/factories/post.rb')).to be(false)

    generate('model', 'Article', config: "#{config}\nconfig.factory_bakery.generators = true")
    expect(exists?('test/factories/article.rb')).to be(true)
  end

  it 'uses the first configured path and replaces existing definitions only with force' do
    config = 'config.factory_bakery.definition_paths = %w[custom/first custom/second]'
    path = 'custom/first/post.rb'
    write(path, '# retained')

    generate('factory_bakery:definition', 'Post', config: config)
    expect(contents(path)).to eq('# retained')

    generate('factory_bakery:definition', 'Post', '--force', config: config)
    expect(contents(path)).to include('FactoryBakery.define(Post) do')
    expect(exists?('custom/second/post.rb')).to be(false)
  end

  it 'installs a commented initializer and the conventional directory' do
    generate('factory_bakery:install')

    expect(contents('config/initializers/factory_bakery.rb')).to include(
      '# config.associations', '# config.definition_paths', '# config.fill_optional', '# config.generators'
    )
    expect(File.directory?(File.join(@root, 'test/factories'))).to be(true)
  end

  it 'uses the RSpec default for standalone generation before any factory directory exists' do
    generate('factory_bakery:definition', 'Post', config: 'config.generators.test_framework :rspec')

    expect(exists?('spec/factories/post.rb')).to be(true)
  end

  it 'applies fill_optional at Rails boot' do
    config = 'config.factory_bakery.fill_optional = [:title]'
    write('config/initializers/verify_bakery.rb', <<~RUBY)
      Rails.application.config.after_initialize do
        abort 'fill_optional was not applied' unless FactoryBakery.fill_optional == ['title']
      end
    RUBY

    generate('factory_bakery:install', config: config)
  end

  it 'separates FactoryBot files discovered before the installer runs' do
    write('spec/factories/posts.rb', 'FactoryBot.define { factory :post }')
    generate('factory_bakery:install', config: 'config.generators.test_framework :rspec')

    expect(contents('config/initializers/factory_bakery.rb')).to include('config.definition_paths = ["spec/bakery"]')
    expect(File.directory?(File.join(@root, 'spec/bakery'))).to be(true)
  end

  it 'separates definitions when FactoryBot is loaded' do
    generate('factory_bakery:install', before_boot: 'module FactoryBot; end')

    expect(contents('config/initializers/factory_bakery.rb')).to include('config.definition_paths = ["test/bakery"]')
  end
end
