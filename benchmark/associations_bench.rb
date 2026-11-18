# frozen_string_literal: true

# Association benchmark: query shape, allocations and reflection scans.
#
# Run (Ruby 3.4.3, one of the appraisal gemfiles):
#   BUNDLE_GEMFILE=gemfiles/rails8.0.gemfile mise exec ruby@3.4.3 -- \
#     ruby benchmark/associations_bench.rb
#
# Optional env: BENCH_ITERATIONS (default 1000), BENCH_WARMUP (default 50).
#
# The script asserts deterministic query shapes and the absence of warm
# reflection rescans. Violations are collected and printed, then the process
# exits non-zero so regressions fail loudly.

# A benchmark is one self-contained harness: it intentionally keeps the
# schema, scenarios and measurement loop together in a single module.
# rubocop:disable Metrics/ModuleLength, Metrics/MethodLength, Metrics/AbcSize
# rubocop:disable Metrics/ParameterLists, Metrics/CyclomaticComplexity
# rubocop:disable Metrics/PerceivedComplexity, Style/Documentation

require 'bundler/setup'
require 'active_record'
require 'active_support/notifications'
require 'factory_bakery'
require 'factory_bakery/associations'

module AssocBench
  ITERATIONS = Integer(ENV.fetch('BENCH_ITERATIONS', '1000'))
  WARMUP = Integer(ENV.fetch('BENCH_WARMUP', '50'))
  TABLES = %w[comments posts authors widgets].freeze

  class << self
    attr_accessor :reflection_scans
  end
  self.reflection_scans = 0

  # Counts SQL statements emitted while a probe is active. SCHEMA statements
  # and cached-query notifications are infrastructure, not bake queries.
  class QueryCounter
    def initialize
      @counts = Hash.new(0)
      @subscriber = nil
      @paused = false
    end

    def start!
      return if @subscriber

      @subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        next if @paused || payload[:name] == 'SCHEMA' || payload[:cached]

        sql = payload[:sql].to_s.lstrip
        kind =
          case sql
          when /\ASELECT\b/i then :select
          when /\AINSERT\b/i then :insert
          when /\AUPDATE\b/i then :update
          when /\ADELETE\b/i then :delete
          else :other
          end
        @counts[kind] += 1
      end
    end

    def stop!
      return unless @subscriber

      ActiveSupport::Notifications.unsubscribe(@subscriber)
      @subscriber = nil
    end

    def reset!
      @counts.clear
    end

    # Setup SQL (truncating tables, seeding reuse rows) is not part of a bake.
    def pause!
      @paused = true
    end

    def resume!
      @paused = false
    end

    def select = @counts[:select]
    def insert = @counts[:insert]
  end

  # Wraps the reflection API on our model classes to prove that a warm bake
  # does not rescan reflections. Production code is untouched.
  module ReflectionProbe
    def reflect_on_all_associations(*args)
      AssocBench.reflection_scans += 1
      super
    end
  end

  # ---------------------------------------------------------------- schema

  def self.setup_database!
    ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: ':memory:')
    connection = ActiveRecord::Base.connection
    connection.execute('PRAGMA foreign_keys = ON')

    connection.create_table(:authors, force: true) do |t|
      t.string :name
      t.string :email
      t.json :metadata
      t.datetime :created_at
      t.datetime :updated_at
    end
    connection.create_table(:posts, force: true) do |t|
      t.integer :author_id, null: false
      t.string :title
      t.string :slug
      t.json :metadata
      t.integer :comments_count, default: 0
      t.datetime :created_at
      t.datetime :updated_at
    end
    connection.create_table(:comments, force: true) do |t|
      t.integer :post_id, null: false
      t.integer :author_id, null: false
      t.text :body
      t.json :metadata
      t.datetime :created_at
      t.datetime :updated_at
    end
    connection.create_table(:widgets, force: true) do |t|
      t.string :name
      t.string :code
      t.integer :quantity
      t.json :metadata
      t.datetime :created_at
      t.datetime :updated_at
    end
  end

  class Author < ActiveRecord::Base
    validates :name, presence: true
    validates :email, presence: true, format: { with: /\A[a-zA-Z0-9@._+-]+\z/ }
  end

  class Post < ActiveRecord::Base
    belongs_to :author, optional: false
    has_many :comments

    validates :title, presence: true, uniqueness: true
    validates :slug, presence: true, uniqueness: true, format: { with: /\A[a-z0-9-]+\z/ }
  end

  class Comment < ActiveRecord::Base
    belongs_to :post, optional: false
    belongs_to :author, optional: false

    validates :body, presence: true
  end

  class Widget < ActiveRecord::Base
    validates :name, presence: true, uniqueness: true
    validates :code, presence: true, uniqueness: true, format: { with: /\A[A-Za-z0-9-]+\z/ }
  end

  FactoryBakery.define(:bench_widget, klass: Widget) do
    name { 'declared-widget' }

    trait :tagged do
      code { 'declared-code' }
    end
  end

  # ------------------------------------------------------------ assertions

  def self.violations
    @violations ||= []
  end

  def self.check(label, actual, expected)
    return if actual == expected

    violations << "#{label}: expected #{expected}, got #{actual}"
  end

  def self.check_at_least(label, actual, expected)
    return if actual >= expected

    violations << "#{label}: expected >= #{expected}, got #{actual}"
  end

  # -------------------------------------------------------------- measuring

  def self.clear_tables!
    connection = ActiveRecord::Base.connection
    TABLES.reverse_each { |table| connection.execute("DELETE FROM #{table}") }
  end

  def self.seed_reusable_rows!
    author = Author.create!(name: 'seed-author', email: 'seed@example.com', metadata: {})
    Post.create!(author: author, title: 'seed-title', slug: 'seed-slug', metadata: {})
  end

  # One cold bake with a fresh database and a SQL probe, then a warm loop with
  # GC disabled. Allocations come from GC.stat's monotonic allocation counter.
  def self.measure_scenario(name, prepare:, target:, traits: [], persist: false, expect: {})
    prepare.call
    queries = QueryCounter.new
    scans_before = reflection_scans
    queries.start!
    invoke(target, traits, persist)
    queries.stop!
    cold_scans = reflection_scans - scans_before
    cold_select = queries.select
    cold_insert = queries.insert

    expected_select = expect[:select]
    check("#{name} bake/bake! SELECTs", cold_select, expected_select) if expected_select
    check("#{name} bake/bake! INSERTs", cold_insert, expect[:insert]) if expect[:insert]
    check_at_least("#{name} cold reflection scans", cold_scans, 1) if expect[:reflection_scan_baseline]

    WARMUP.times do
      prepare.call
      invoke(target, traits, persist)
    end

    queries.reset!
    queries.start!
    GC.disable
    allocations_before = GC.stat(:total_allocated_objects)
    scans_before = reflection_scans
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    ITERATIONS.times do
      queries.pause!
      prepare.call
      queries.resume!
      invoke(target, traits, persist)
    end
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    allocations_after = GC.stat(:total_allocated_objects)
    warm_scans = reflection_scans - scans_before
    GC.enable
    queries.stop!

    warm_select = queries.select.to_f / ITERATIONS
    warm_insert = queries.insert.to_f / ITERATIONS
    check("#{name} warm SELECTs/bake", warm_select, expected_select) if expected_select
    check("#{name} warm INSERTs/bake", warm_insert, expect[:insert]) if expect[:insert]
    check("#{name} warm reflection scans/bake", warm_scans, 0)

    {
      name: name,
      cold_sel: cold_select,
      cold_ins: cold_insert,
      cold_scans: cold_scans,
      warm_sel: warm_select,
      warm_ins: warm_insert,
      scans_per_bake: warm_scans.to_f / ITERATIONS,
      allocations: (allocations_after - allocations_before).to_f / ITERATIONS,
      ips: ITERATIONS / elapsed
    }
  end

  def self.invoke(target, traits, persist)
    if persist
      FactoryBakery.bake!(target, *traits)
    else
      FactoryBakery.bake(target, *traits)
    end
  end

  # --------------------------------------------------------------- scenarios

  def self.scenarios
    [
      {
        name: 'core heuristics (plugin off)',
        plugin: false,
        target: Widget,
        prepare: -> { clear_tables! },
        expect: { select: 2, insert: 0, reflection_scan_baseline: false }
      },
      {
        name: 'define + traits (plugin off)',
        plugin: false,
        target: :bench_widget,
        traits: [:tagged],
        prepare: -> { clear_tables! },
        expect: { select: 0, insert: 0 }
      },
      {
        name: 'required_only chain bake',
        plugin: true,
        mode: :required_only,
        target: Comment,
        prepare: -> { clear_tables! },
        expect: { select: 2, insert: 0, reflection_scan_baseline: true }
      },
      {
        name: 'required_only chain bake!',
        plugin: true,
        mode: :required_only,
        target: Comment,
        persist: true,
        prepare: -> { clear_tables! },
        expect: { select: 4, insert: 4 }
      },
      {
        name: ':all default_count=1 bake!',
        plugin: true,
        mode: :all,
        default_count: 1,
        target: Post,
        persist: true,
        prepare: -> { clear_tables! },
        expect: { select: 4, insert: 4 }
      },
      {
        name: ':all default_count=3 bake!',
        plugin: true,
        mode: :all,
        default_count: 3,
        target: Post,
        persist: true,
        prepare: -> { clear_tables! },
        expect: { select: 4, insert: 8 }
      },
      {
        name: ':reuse rows present bake!',
        plugin: true,
        mode: :required_only,
        strategy: :reuse,
        target: Comment,
        persist: true,
        prepare: lambda {
          clear_tables!
          seed_reusable_rows!
        },
        expect: { select: 2, insert: 1 }
      },
      {
        name: ':reuse rows absent bake!',
        plugin: true,
        mode: :required_only,
        strategy: :reuse,
        target: Comment,
        persist: true,
        prepare: -> { clear_tables! },
        expect: { insert: 3 }
      }
    ]
  end

  def self.run!
    setup_database!

    [Widget, Author, Post, Comment].each { |klass| klass.singleton_class.prepend(ReflectionProbe) }

    print_row(['scenario', 'cSEL', 'cINS', 'wSEL', 'wINS', 'scn/bake', 'alloc/bake', 'k ips'])

    rows = scenarios.map do |scenario|
      warn "-> #{scenario[:name]}"
      configure_plugin(scenario)
      settings = {}
      settings[:mode] = scenario[:mode] if scenario[:mode]
      settings[:strategy] = scenario[:strategy] if scenario[:strategy]
      settings[:default_count] = scenario[:default_count] if scenario[:default_count]

      FactoryBakery::Associations.with(**settings) do
        measure_scenario(
          scenario[:name],
          prepare: scenario[:prepare],
          target: scenario[:target],
          traits: scenario.fetch(:traits, []),
          persist: scenario.fetch(:persist, false),
          expect: scenario.fetch(:expect, {})
        )
      end
    end

    rows.each do |row|
      print_row(
        [row[:name], row[:cold_sel], row[:cold_ins], row[:warm_sel], row[:warm_ins],
         row[:scans_per_bake].round(3), row[:allocations].round, (row[:ips] / 1000.0).round(1)]
      )
    end

    puts
    if violations.empty?
      puts "Assertions: all passed (#{ITERATIONS} iterations/scenario, #{WARMUP} warmup)."
    else
      puts "Assertions FAILED (#{violations.length}):"
      violations.each { |violation| puts "  - #{violation}" }
    end

    violations.empty? ? 0 : 1
  end

  # Fixed-width table row; the first column is left-aligned, the rest right.
  def self.print_row(cells)
    formatted = cells.each_with_index.map do |cell, index|
      index.zero? ? cell.to_s.ljust(30) : cell.to_s.rjust(9)
    end
    puts formatted.join(' ')
  end

  def self.configure_plugin(scenario)
    FactoryBakery::Associations.reset_configuration!
    FactoryBakery.reset_plugins!
    return unless scenario[:plugin]

    FactoryBakery.register_plugin(FactoryBakery::Associations::Plugin)
  end
end

exit AssocBench.run!
# rubocop:enable Metrics/ModuleLength, Metrics/MethodLength, Metrics/AbcSize
# rubocop:enable Metrics/ParameterLists, Metrics/CyclomaticComplexity
# rubocop:enable Metrics/PerceivedComplexity, Style/Documentation
