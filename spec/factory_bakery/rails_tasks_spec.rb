# frozen_string_literal: true

require 'rake'
require 'tmpdir'
require 'fileutils'

RSpec.describe 'FactoryBakery rake tasks' do
  around do |example|
    previous_app = Rails.application
    Dir.mktmpdir do |root|
      Rake.with_application do
        app = Class.new(Rails::Application).instance
        app.config.root = root
        Rails.application = app
        @root = root
        prepare_autoloaders(app, example)
        app.load_tasks
        begin
          example.run
        ensure
          app.autoloaders.each(&:unregister)
          Object.send(:remove_const, :RakeLazyModel) if Object.const_defined?(:RakeLazyModel, false)
        end
      end
    end
  ensure
    Rails.application = previous_app
  end

  def prepare_autoloaders(app, example)
    if example.metadata[:lazy_model]
      models = File.join(@root, 'app/models')
      FileUtils.mkdir_p(models)
      File.write(File.join(models, 'rake_lazy_model.rb'), 'class RakeLazyModel < ActiveRecord::Base; end')
      app.autoloaders.main.push_dir(models)
    end
    app.autoloaders.each(&:setup)
  end

  def invoke(task, *models)
    Rake::Task["factory_bakery:#{task}"].invoke(*models)
  end

  def definition(name)
    File.join(@root, "test/factories/#{name}.rb")
  end

  def with_flag(name)
    previous = ENV[name]
    ENV[name] = '1'
    yield
  ensure
    ENV[name] = previous
  end

  it 'writes definitions for each named model' do
    first = define_model('RakeArticle')
    second = define_model('RakeAuthor')

    expect { invoke(:definitions, first.name, second.name) }.to output(/create/).to_stdout
    expect(File.read(definition('rake_article'))).to include('FactoryBakery.define(RakeArticle)')
    expect(File.read(definition('rake_author'))).to include('FactoryBakery.define(RakeAuthor)')
  end

  it 'eager loads models and writes only missing definitions when no names are supplied', :lazy_model do
    registered = define_model('RakeRegistered')
    abstract = define_class('RakeAbstract', ActiveRecord::Base) { self.abstract_class = true }
    FactoryBakery.define(registered) {}

    expect { invoke(:definitions) }.to output(/create.*rake_lazy_model/).to_stdout
    expect(File.exist?(definition('rake_lazy_model'))).to be(true)
    [registered, abstract].each do |model|
      expect(File.exist?(definition(model.name.underscore))).to be(false)
    end
  end

  it 'includes eager-loaded models when no names are supplied', :lazy_model do
    create_table(:rake_lazy_models)

    with_flag('NO_FAIL') do
      expect { invoke(:doctor) }.to output(/\b[1-9]\d* valid/).to_stdout
    end
    expect(RakeLazyModel.count).to eq(0)
  end

  it 'succeeds when all of the named models pass' do
    model = define_model('RakeValid')

    expect { invoke(:doctor, model.name) }.to output("1 valid, 0 needs definition\n").to_stdout
    expect(model.count).to eq(0)
  end

  it 'checks validation and persistence separately, preserves existing rows and exits nonzero on failures' do
    audit = define_model('RakeAudit')
    good = define_model('RakeGood')
    good.create!
    failed_validation = define_model('RakeInvalid') do
      validate do
        RakeAudit.create!
        errors.add(:base, 'Custom validation rejected the record')
      end
    end
    failed_save = define_model('RakeNoSave') do
      before_save do
        RakeAudit.create!
        throw :abort
      end
    end
    report = /RakeInvalid: Custom validation rejected the record.*custom-validation.*RakeNoSave:.*1 valid, 2 needs/m

    expect do
      expect { invoke(:doctor, failed_validation.name, good.name, failed_save.name) }
        .to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
    end.to output(report).to_stdout
    expect([audit.count, good.count, failed_save.count]).to eq([0, 1, 0])
  end

  it 'can write failing stubs without exiting nonzero or overwriting an existing stub' do
    bad = define_model('RakeBroken') do
      validate { errors.add(:base, "First line\nsecond line") }
    end
    existing = define_model('RakeExisting') do
      validate { errors.add(:base, 'Existing definition') }
    end
    FileUtils.mkdir_p(File.dirname(definition('rake_existing')))
    File.write(definition('rake_existing'), '# retained')

    with_flag('WRITE') do
      with_flag('NO_FAIL') do
        expect { invoke(:doctor, bad.name, existing.name) }.to output(/0 valid, 2 needs definition/).to_stdout
      end
    end

    expect(File.read(definition('rake_broken'))).to include('# First line', '# second line')
    expect(File.read(definition('rake_existing'))).to eq('# retained')
  end

  it 'classifies unique-value collisions and database rejections' do
    unique = define_model('RakeUnique', code: :string) do
      validates :code, inclusion: { in: ['only'] }, uniqueness: true
    end
    unique.create!(code: 'only')
    not_null = define_model('RakeNotNull', code: { type: :string, null: false }) do
      before_create { self.code = nil }
    end

    with_flag('NO_FAIL') do
      expect { invoke(:doctor, unique.name, not_null.name) }.to output(
        /RakeUnique:.*unique-value-collisions.*RakeNotNull:.*database-constraints/m
      ).to_stdout
    end
    expect([unique.count, not_null.count]).to eq([1, 0])
  end

  it 'classifies undiscovered targets and incomplete persistence' do
    require 'factory_bakery/associations'

    parent = define_model('RakeUnsavedParent')
    incomplete = define_model('RakeIncomplete', parent_id: :integer) do
      belongs_to :parent, class_name: 'RakeUnsavedParent', optional: true, autosave: false
    end
    FactoryBakery.define(incomplete) { parent { FactoryBakery.bake(parent) } }
    missing = define_model('RakeMissingTarget', target_id: :integer, target_type: :string) do
      belongs_to :target, polymorphic: true, optional: false
    end
    FactoryBakery::Associations::RailConfig.configure(:required_only)

    with_flag('NO_FAIL') do
      expect { invoke(:doctor, missing.name, incomplete.name) }.to output(
        /RakeMissingTarget:.*association-target.*RakeIncomplete:.*incomplete-persistence/m
      ).to_stdout
    end
    expect([parent.count, incomplete.count, missing.count]).to eq([0, 0, 0])
  ensure
    FactoryBakery.unregister_plugin(FactoryBakery::Associations::Plugin)
    FactoryBakery::Associations.reset_configuration!
  end
end
