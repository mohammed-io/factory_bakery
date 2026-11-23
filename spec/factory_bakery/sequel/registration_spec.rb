# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'tmpdir'
require 'fileutils'
require_relative 'support/sequel_database'

# Registration behavior of the opt-in Sequel mapper plugin: the require is
# the opt-in switch, registration is idempotent, the mapper claims only
# Sequel::Model descendants, and one process runs the default mapper and the
# Sequel mapper side by side.
RSpec.describe 'Sequel mapper registration' do
  include DefineSequelModelMacros

  it 'raises a helpful FactoryBakery::Error when the sequel gem is absent' do
    dependency_libs = %w[ffaker logger regexp_parser].flat_map do |name|
      ['-I', File.join(Gem::Specification.find_by_name(name).gem_dir, 'lib')]
    end
    code = <<~RUBY
      require 'factory_bakery'

      loaded = false
      begin
        require 'factory_bakery/sequel'
        loaded = true
      rescue FactoryBakery::Error => e
        abort 'the error must be a FactoryBakery::Error' unless e.is_a?(FactoryBakery::Error)
        abort 'the error must name the gem' unless e.message.include?("gem 'sequel'")
        abort 'the error must name the require' unless e.message.include?('factory_bakery/sequel')
        print 'OK'
      end
      abort 'factory_bakery/sequel loaded without the sequel gem' if loaded
    RUBY

    # A genuinely gemless environment: an empty GEM_HOME/GEM_PATH hides every
    # installed gem (the sequel gem is physically installed for this suite),
    # while the runtime dependencies (ffaker, regexp_parser) stay loadable
    # through their lib dirs on $LOAD_PATH, exactly like the architecture
    # guard's framework-free probes.
    gemless_home = Dir.mktmpdir
    stdout, stderr, status = nil
    begin
      Bundler.with_unbundled_env do
        stdout, stderr, status = Open3.capture3(
          { 'GEM_HOME' => gemless_home, 'GEM_PATH' => gemless_home },
          RbConfig.ruby,
          *dependency_libs, '-I', File.expand_path('lib'),
          '-e', code
        )
      end
    ensure
      FileUtils.remove_entry(gemless_home)
    end

    expect(status).to be_success,
                      "requiring the plugin without the gem failed:\n#{stderr}\n#{stdout}"
    expect(stdout).to eq('OK')
  end

  describe 'plugin registration', :sequel_mapper do
    it 'registers a mapper that claims Sequel::Model classes' do
      model = define_sequel_model('SeqRegistered', name: :string)

      mapper = FactoryBakery::MapperRegistry.mapper_for(model)

      expect(mapper).to be_a(FactoryBakery::Sequel::Mapper)
      expect(mapper.supports?(model)).to be(true)
      expect(mapper.supports?(String)).to be_falsey
    end

    it 'is idempotent: requiring again or re-registering the same mapper adds nothing' do
      model = define_sequel_model('SeqIdempotent', name: :string)
      mapper = FactoryBakery::MapperRegistry.mapper_for(model)

      expect { require 'factory_bakery/sequel' }
        .not_to change(FactoryBakery::MapperRegistry, :mappers)
      expect { FactoryBakery::MapperRegistry.register(mapper) }
        .not_to change(FactoryBakery::MapperRegistry, :mappers)
    end

    it 'answers no association introspection, keeping the associations plugin off Sequel classes' do
      model = define_sequel_model('SeqNoAssociations', name: :string)

      expect(FactoryBakery::MapperRegistry.association_introspection(model)).to be_nil
    end
  end

  describe 'coexistence with the default mapper', :sequel_mapper do
    include DefineConstantMacros

    it 'routes each framework to its own mapper in one process' do
      sequel_model = define_sequel_model('SeqCoexists', name: :string)
      ar_model = define_model('ArCoexists', name: :string)

      sequel_mapper = FactoryBakery::MapperRegistry.mapper_for(sequel_model)
      ar_mapper = FactoryBakery::MapperRegistry.mapper_for(ar_model)

      expect(sequel_mapper).to be_a(FactoryBakery::Sequel::Mapper)
      expect(ar_mapper).to be_a(FactoryBakery::ActiveRecordMapper::Mapper)
      expect(ar_mapper).not_to equal(sequel_mapper)

      # Each mapper answers the same contract for its own world.
      expect(FactoryBakery::ConstraintSet.for(sequel_model, 'name').type).to eq(:string)
      expect(FactoryBakery::ConstraintSet.for(ar_model, 'name').type).to eq(:string)
    end

    it 'bakes a Sequel class and a primary-framework class side by side' do
      sequel_model = define_sequel_model('SeqSideBySide', name: { type: :string, null: false })
      ar_model = define_model('ArSideBySide', name: :string)

      sequel_record = FactoryBakery.bake!(sequel_model)
      ar_record = FactoryBakery.bake!(ar_model)

      expect(sequel_record).not_to be_new
      expect(sequel_model.count).to eq(1)
      expect(ar_record).to be_persisted
      expect(ar_model.count).to eq(1)
    end
  end
end
