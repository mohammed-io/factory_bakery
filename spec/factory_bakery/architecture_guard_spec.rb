# frozen_string_literal: true

require 'spec_helper'
require 'open3'

# The enforcement of the framework-agnostic core: no file in the core set may
# reference the ActiveRecord, ActiveModel, Rails or ActiveSupport constants,
# so agnosticism cannot silently regress. Excluded from the core set are the
# default mapper plugin (lib/factory_bakery/active_record_mapper/**), the
# opt-in associations plugin internals (lib/factory_bakery/associations/**)
# the Rails generators (lib/generators/factory_bakery/**), and the opt-in
# Tapioca compiler (lib/tapioca/dsl/compilers/factory_bakery.rb).
RSpec.describe 'framework-agnostic core architecture guard' do
  let(:core_exclusions) do
    [
      %r{\Alib/factory_bakery/active_record_mapper(?:\.rb|/|\z)},
      %r{\Alib/factory_bakery/associations(?:/|\z)},
      %r{\Alib/factory_bakery/(?:rspec|minitest)\.rb\z},
      %r{\Alib/generators/factory_bakery/},
      %r{\Alib/tapioca/dsl/compilers/factory_bakery\.rb\z}
    ]
  end

  # The optional test-framework integrations (lib/factory_bakery/rspec.rb and
  # minitest.rb) are the only files that name a test framework.
  let(:forbidden_test_framework_references) { /\b(?:RSpec|Minitest)\b/ }

  # Constant references, including name-string matching (validator classes
  # are matched by name in the mapper, never in the core) and any textual
  # mention in comments. ActiveSupport is included: the core's date and
  # datetime arithmetic is stdlib-only.
  let(:forbidden_constant_references) { /\b(?:ActiveRecord|ActiveModel|Rails|ActiveSupport)\b/ }

  # Requiring a framework gem is a dependency, not just a mention.
  let(:forbidden_framework_requires) do
    /\brequire\s*\(?\s*['"](?:rails|active_record|active_model|active_support)['"]/
  end

  def core_files
    Dir.glob('lib/**/*.rb').reject do |path|
      core_exclusions.any? { |pattern| path.match?(pattern) }
    end.sort
  end

  def violations_in(files, pattern)
    files.flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, index|
        "#{path}:#{index + 1}: #{line.strip}" if line.match?(pattern)
      end
    end
  end

  it 'protects a real core set' do
    expect(core_files).to include(
      'lib/factory_bakery.rb',
      'lib/factory_bakery/bakery_builder.rb',
      'lib/factory_bakery/mapper_registry.rb',
      'lib/factory_bakery/constraint_set.rb',
      'lib/factory_bakery/uniqueness_enforcer.rb',
      'lib/factory_bakery/persistence_verifier.rb',
      'lib/factory_bakery/attribute_fillers/filler_selector.rb',
      'lib/factory_bakery/attribute_fillers/string_filler.rb',
      'lib/factory_bakery/attribute_fillers/value_resolution.rb'
    )

    # The excluded plugin worlds must exist, otherwise the exclusions quietly
    # guard nothing.
    expect(File.exist?('lib/factory_bakery/active_record_mapper.rb')).to be(true)
    expect(File.exist?('lib/factory_bakery/active_record_mapper/mapper.rb')).to be(true)
    expect(File.exist?('lib/factory_bakery/active_record_mapper/railtie.rb')).to be(true)
    expect(File.exist?('lib/factory_bakery/associations/plugin.rb')).to be(true)
  end

  it 'is armed: the excluded mapper plugin really does reference its framework' do
    # A canary proving the pattern catches genuine references. If this ever
    # fails, the core assertions above are guarding nothing.
    expect(File.read('lib/factory_bakery/active_record_mapper/mapper.rb'))
      .to match(forbidden_constant_references)
  end

  it 'is armed: the excluded Rails integration really does reference ActiveSupport' do
    # A canary proving the extended pattern catches ActiveSupport references
    # too, not just the ORM constants.
    expect(File.read('lib/factory_bakery/active_record_mapper/railtie.rb'))
      .to match(forbidden_constant_references)
  end

  it 'keeps every framework constant reference out of the core set' do
    violations = violations_in(core_files, forbidden_constant_references)

    message = "framework constants leaked into the framework-agnostic core:\n#{violations.join("\n")}"
    expect(violations).to be_empty, message
  end

  it 'keeps test-framework names out of the core set' do
    # Comments may show RSpec or Minitest usage (the public mixin's docs), so
    # only code lines are checked.
    violations = core_files.flat_map do |path|
      File.readlines(path).each_with_index.filter_map do |line, index|
        next if line.lstrip.start_with?('#')

        "#{path}:#{index + 1}: #{line.strip}" if line.match?(forbidden_test_framework_references)
      end
    end

    message = "test-framework names leaked into the framework-agnostic core:\n#{violations.join("\n")}"
    expect(violations).to be_empty, message
  end

  it 'keeps every framework require out of the core set' do
    violations = violations_in(core_files, forbidden_framework_requires)

    message = "framework requires leaked into the framework-agnostic core:\n#{violations.join("\n")}"
    expect(violations).to be_empty, message
  end

  it 'loads the gem and bakes a plain target with no framework boot at all' do
    ffaker_lib = File.join(Gem::Specification.find_by_name('ffaker').gem_dir, 'lib')
    code = <<~RUBY
      require 'factory_bakery'

      abort 'the gem must not load the framework on its own' if defined?(Rails)
      abort 'the gem must not load Sorbet tooling on its own' if defined?(Tapioca) || defined?(FactoryBakery::Sorbet)

      class GuardSpecPoro
        attr_accessor :greeting
      end

      FactoryBakery.define(GuardSpecPoro) { greeting { 'framework-free' } }
      value = FactoryBakery.bake(GuardSpecPoro).greeting
      abort 'plain bake is broken outside frameworks' unless value == 'framework-free'

      print 'OK'
    RUBY

    stdout, stderr, status = nil
    Bundler.with_unbundled_env do
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        '-I', ffaker_lib, '-I', File.expand_path('lib'),
        '-e', code
      )
    end

    expect(status).to be_success, "framework-free load failed:\n#{stderr}\n#{stdout}"
    expect(stdout).to eq('OK')
  end

  it 'runs the temporal generation arithmetic with no framework boot at all' do
    ffaker_lib = File.join(Gem::Specification.find_by_name('ffaker').gem_dir, 'lib')
    code = <<~RUBY
      # The core's temporal arithmetic is stdlib-only: load the unit directly,
      # with nothing but the stdlib requires it needs, and verify no framework
      # came with it.
      require 'date'
      require 'time'
      require 'factory_bakery/attribute_fillers/temporal_arithmetic'

      frameworks = [defined?(Rails), defined?(ActiveRecord), defined?(ActiveSupport)]
      abort 'the core temporal unit must stay framework-free' if frameworks.any?

      arithmetic = FactoryBakery::AttributeFillers::TemporalArithmetic

      # Date arithmetic: calendar years and plain days, stdlib only.
      today = Date.today
      birthday = arithmetic.date_plus_years(today, -rand(18..90))
      age_days = (today - birthday).to_i
      abort 'year arithmetic is off' unless age_days / 365 >= 18 && age_days / 365 <= 90

      start_date = arithmetic.date_plus_days(today, -rand(0..365))
      abort 'day arithmetic is off' unless (today - start_date).to_i.between?(0, 365)

      # Time arithmetic: a calendar day shift keeps the wall clock.
      now = Time.now
      stamp = arithmetic.time_plus_days(now, -30)
      abort 'day shift is off' unless stamp.to_date == (now.to_date - 30)

      future = arithmetic.time_plus_years(now, 1)
      abort 'year shift is off' unless future.year == now.year + 1

      later = arithmetic.plus_seconds(now, 3600)
      abort 'second arithmetic is off' unless later > now

      print 'OK'
    RUBY

    stdout, stderr, status = nil
    Bundler.with_unbundled_env do
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby,
        '-I', ffaker_lib, '-I', File.expand_path('lib'),
        '-e', code
      )
    end

    expect(status).to be_success, "framework-free temporal arithmetic failed:\n#{stderr}\n#{stdout}"
    expect(stdout).to eq('OK')
  end
end
