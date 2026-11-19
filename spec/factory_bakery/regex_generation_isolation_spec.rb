# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'open3'
require 'prism'
require 'tmpdir'

# The regex generator is a self-contained unit: Ruby stdlib and regexp_parser
# only. Every constant its source mentions must be one it defines itself, a
# regexp_parser constant, or an explicitly allowed Ruby core constant. Anything
# else (another FactoryBakery constant, FFaker, ActiveRecord, ActiveModel, ...)
# fails the suite. The check reads the code with Prism, so comments and strings
# never count.
module RegexGenerationIsolation
  ENTRY_FILE = 'lib/factory_bakery/regex_generation.rb'
  NAMESPACE_PARTS = %w[FactoryBakery RegexGeneration].freeze
  OWN_NAMESPACE = 'FactoryBakery::RegexGeneration::'

  # Ruby core constants the generator is allowed to use. Keep this minimal.
  ALLOWED_CORE = %w[
    Array Encoding::BINARY Encoding::UTF_8 Float::INFINITY Mutex Random Regexp
    Regexp::IGNORECASE Regexp::MULTILINE Regexp::NOENCODING StandardError String Struct
  ].freeze
  # Everything under these is regexp_parser's.
  ALLOWED_REGEXP_PARSER = %w[Regexp::Parser Regexp::Expression Regexp::Scanner Regexp::Syntax].freeze

  # Collects every constant reference (with its line) and every constant the
  # code defines. A constant path is taken whole and not descended into.
  class ConstantCollector < Prism::Visitor
    attr_reader :references, :definitions

    def initialize
      super
      @references = []
      @definitions = []
    end

    def visit_constant_read_node(node)
      @references << [node.name.to_s, node.location.start_line]
    end

    def visit_constant_path_node(node)
      @references << [node.slice.delete_prefix('::'), node.location.start_line]
    end

    def visit_module_node(node)
      @definitions << node.constant_path.slice
      super
    end

    def visit_class_node(node)
      @definitions << node.constant_path.slice
      super
    end

    def visit_constant_write_node(node)
      @definitions << node.name.to_s
      super
    end
  end

  def guarded_files
    [ENTRY_FILE, *Dir.glob('lib/factory_bakery/regex_generation/**/*.rb').sort]
  end

  def collect(trees)
    trees.transform_values do |tree|
      ConstantCollector.new.tap { |collector| tree.accept(collector) }
    end
  end

  def allowed?(path, own)
    return true if NAMESPACE_PARTS.include?(path) || path == NAMESPACE_PARTS.join('::')
    return true if ALLOWED_CORE.include?(path)
    return true if ALLOWED_REGEXP_PARSER.any? { |prefix| path == prefix || path.start_with?("#{prefix}::") }

    local = path.delete_prefix(OWN_NAMESPACE).delete_prefix('RegexGeneration::')
    own.include?(local.split('::').first)
  end

  # "path:line: Constant" for every reference that resolves to nothing allowed.
  def violations_in(trees)
    collected = collect(trees)
    own = collected.values.flat_map(&:definitions).uniq - NAMESPACE_PARTS
    collected.flat_map do |path, collector|
      collector.references.reject { |name, _line| allowed?(name, own) }
               .map { |name, line| "#{path}:#{line}: #{name}" }
    end
  end

  def parse_files(paths)
    paths.to_h { |path| [path, Prism.parse_file(path).value] }
  end
end

RSpec.describe 'regex generation isolation' do
  include RegexGenerationIsolation

  it 'guards a real, non-empty file set that includes the entry file' do
    expect(guarded_files).to include(RegexGenerationIsolation::ENTRY_FILE)
    expect(guarded_files.size).to be > 5
    expect(guarded_files).to all(satisfy { |path| File.file?(path) })
  end

  it 'references only its own constants, regexp_parser and allowed Ruby core constants' do
    violations = violations_in(parse_files(guarded_files))

    expect(violations).to be_empty,
                          "lib/factory_bakery/regex_generation must stay self-contained, found:\n" \
                          "#{violations.join("\n")}"
  end

  it 'is armed: it reports another FactoryBakery constant and a framework constant' do
    source = <<~RUBY
      module FactoryBakery
        module RegexGeneration
          def self.x = ConstraintSet.new && ::FFaker::Name
        end
      end
    RUBY

    violations = violations_in('canary.rb' => Prism.parse(source).value)

    expect(violations).to contain_exactly('canary.rb:3: ConstraintSet', 'canary.rb:3: FFaker::Name')
  end

  it 'is armed: it rejects qualified references outside its own namespace' do
    source = <<~RUBY
      module FactoryBakery
        module RegexGeneration
          Plan = Struct.new(:a)
          OK = FactoryBakery::RegexGeneration::Plan.new(RegexGeneration::Plan)
          BAD = [FactoryBakery::Plan, FactoryBakery::Error, ActiveRecord::Base, ActiveModel]
        end
      end
    RUBY

    violations = violations_in('canary.rb' => Prism.parse(source).value)

    expect(violations).to contain_exactly(
      'canary.rb:5: FactoryBakery::Plan', 'canary.rb:5: FactoryBakery::Error',
      'canary.rb:5: ActiveRecord::Base', 'canary.rb:5: ActiveModel'
    )
  end

  it 'loads and generates with nothing but Ruby and regexp_parser available' do
    parser_lib = File.join(Gem::Specification.find_by_name('regexp_parser').gem_dir, 'lib')
    code = <<~RUBY
      require 'factory_bakery/regex_generation'

      leaked = FactoryBakery.constants - [:RegexGeneration]
      abort "FactoryBakery constants leaked: \#{leaked}" unless leaked.empty?

      frameworks = %i[FFaker ActiveRecord ActiveModel ActiveSupport Rails].select { |name| Object.const_defined?(name) }
      abort "frameworks loaded: \#{frameworks}" unless frameworks.empty?

      regexp = /\\A[^@\\s]+@[^@\\s]+\\z/
      value = FactoryBakery::RegexGeneration.generate(regexp)
      abort "no value or mismatch: \#{value.inspect}" unless value&.match?(regexp)

      print 'OK'
    RUBY

    # An empty GEM_HOME/GEM_PATH hides every installed gem: only regexp_parser's
    # lib dir (on $LOAD_PATH) and this repo's lib are reachable.
    gemless_home = Dir.mktmpdir
    stdout, stderr, status = nil
    begin
      Bundler.with_unbundled_env do
        stdout, stderr, status = Open3.capture3(
          { 'GEM_HOME' => gemless_home, 'GEM_PATH' => gemless_home },
          RbConfig.ruby, '-I', parser_lib, '-I', File.expand_path('lib'), '-e', code
        )
      end
    ensure
      FileUtils.remove_entry(gemless_home)
    end

    expect(status).to be_success, "isolated load failed:\n#{stderr}\n#{stdout}"
    expect(stdout).to eq('OK')
  end
end
