# frozen_string_literal: true

# Shared harness for the FactoryBakery vs factory_bot benchmarks in this
# directory: one schema, equivalent factories for both libraries, and the
# probes that count SQL statements, `valid?` calls and allocations per call.
#
# DATABASE_URL selects the database (in-memory SQLite when unset), exactly as
# the spec suite does. The schema is created with `force: :cascade`, so point
# it at a scratch database, never at an application's.

# A benchmark harness keeps schema, factories and probes together on purpose.
# rubocop:disable Metrics/ModuleLength, Metrics/MethodLength, Metrics/AbcSize
# rubocop:disable Style/Documentation

require 'bundler/setup'
require 'logger'
require 'active_record'
require 'active_support/notifications'
require 'factory_bakery'
require 'factory_bakery/associations'
require 'factory_bot'

FactoryBakery.logger = Logger.new(nil)

module PerfBench
  # ------------------------------------------------------------------ probes

  # Counts `valid?` on every ActiveRecord model. ActiveRecord's `save!` calls
  # `valid?` too, so a persisted call always counts at least one.
  module ValidCounter
    def valid?(*args)
      PerfBench.valid_calls += 1
      super
    end
  end

  class << self
    attr_accessor :valid_calls
  end
  self.valid_calls = 0

  # SQL statements by kind, excluding schema introspection and cached reads.
  class QueryCounter
    KINDS = {
      /\ASELECT\b/i => :select, /\AINSERT\b/i => :insert, /\AUPDATE\b/i => :update,
      /\ADELETE\b/i => :delete, /\A(SAVEPOINT|RELEASE)\b/i => :savepoint,
      /\AROLLBACK\b/i => :rollback, /\A(BEGIN|COMMIT)\b/i => :transaction
    }.freeze

    attr_reader :counts

    def initialize
      @counts = Hash.new(0)
    end

    def measure
      subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
        next if payload[:name] == 'SCHEMA' || payload[:cached]

        sql = payload[:sql].to_s.lstrip
        @counts[KINDS.find { |pattern, _| pattern.match?(sql) }&.last || :other] += 1
      end
      yield
      self
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end
  end

  # ------------------------------------------------------------------ schema

  def self.database_label
    url = ENV.fetch('DATABASE_URL', '')
    url.empty? ? 'sqlite3 (:memory:)' : ActiveRecord::Base.connection.adapter_name
  end

  def self.setup_database!
    url = ENV.fetch('DATABASE_URL', '')
    ActiveRecord::Base.establish_connection(url.empty? ? { adapter: 'sqlite3', database: ':memory:' } : url)
    ActiveRecord::Base.logger = nil
    ActiveRecord::Migration.verbose = false
    connection = ActiveRecord::Base.connection
    connection.execute('PRAGMA foreign_keys = ON') if connection.adapter_name.match?(/sqlite/i)
    create_schema(connection)
    define_models
    ActiveRecord::Base.prepend(ValidCounter) unless ActiveRecord::Base <= ValidCounter
  end

  def self.create_schema(connection)
    %i[comments posts authors books libraries flat_items accounts profiles notes].each do |table|
      connection.drop_table(table, if_exists: true, force: :cascade)
    end

    connection.create_table(:flat_items) do |t|
      t.string :name, null: false
      t.integer :position, null: false
      t.boolean :active, null: false, default: true
      t.text :notes
      t.timestamps
    end

    connection.create_table(:accounts) do |t|
      t.string :email
      t.string :username
      t.string :status
      t.integer :role
      t.text :bio
      t.timestamps
    end
    connection.add_index(:accounts, :email, unique: true)
    connection.add_index(:accounts, :username, unique: true)

    connection.create_table(:authors) do |t|
      t.string :name, null: false
      t.timestamps
    end
    connection.create_table(:posts) do |t|
      t.references :author, null: false, foreign_key: true
      t.string :title, null: false
      t.timestamps
    end
    connection.create_table(:comments) do |t|
      t.references :post, null: false, foreign_key: true
      t.text :body, null: false
      t.timestamps
    end

    connection.create_table(:libraries) do |t|
      t.string :name, null: false
      t.timestamps
    end
    connection.create_table(:books) do |t|
      t.references :library, null: false, foreign_key: true
      t.string :title, null: false
      t.timestamps
    end

    connection.create_table(:profiles) do |t|
      t.string :name, null: false
      t.text :bio
      t.string :website
      t.timestamps
    end

    connection.create_table(:notes) do |t|
      t.string :title, null: false
      t.text :body
      t.timestamps
    end
  end

  def self.define_models
    return if const_defined?(:FlatItem, false)

    model = ->(name, &body) { const_set(name, Class.new(ActiveRecord::Base, &body)) }

    # Flat: a few NOT NULL columns, no validators.
    model.call(:FlatItem) { self.table_name = 'flat_items' }

    # Validated: presence, length, format, uniqueness, inclusion, enum.
    model.call(:Account) do
      self.table_name = 'accounts'
      enum :role, { member: 0, admin: 1, owner: 2 }
      validates :email, presence: true, uniqueness: true, format: { with: /\A[a-z0-9._]+@[a-z0-9]+\.[a-z]{2,4}\z/ }
      validates :username, presence: true, uniqueness: true, length: { in: 3..20 }, format: { with: /\A[a-z0-9_]+\z/ }
      validates :status, inclusion: { in: %w[active pending suspended] }
      validates :role, presence: true
    end

    # belongs_to chain: Comment -> Post -> Author (three records).
    model.call(:Author) do
      self.table_name = 'authors'
      validates :name, presence: true
    end
    model.call(:Post) do
      self.table_name = 'posts'
      belongs_to :author, class_name: 'PerfBench::Author', optional: false
      validates :title, presence: true
    end
    model.call(:Comment) do
      self.table_name = 'comments'
      belongs_to :post, class_name: 'PerfBench::Post', optional: false
      validates :body, presence: true
    end

    # has_many, built in :all mode.
    model.call(:Library) do
      self.table_name = 'libraries'
      has_many :books, class_name: 'PerfBench::Book', inverse_of: :library
      validates :name, presence: true
    end
    model.call(:Book) do
      self.table_name = 'books'
      belongs_to :library, class_name: 'PerfBench::Library', optional: false, inverse_of: :books
      validates :title, presence: true
    end

    # Fallback: a custom validation demands an optional (nullable) column, so
    # the lean attempt is invalid and is rebuilt with optional fills.
    model.call(:Profile) do
      self.table_name = 'profiles'
      validates :name, presence: true
      validate { errors.add(:bio, :blank) if bio.blank? }
    end

    # Probe only: a custom validation the lean record passes. The fallback
    # probes it with `valid?` but never rebuilds.
    model.call(:Note) do
      self.table_name = 'notes'
      validates :title, presence: true
      validate { errors.add(:title, :invalid) if title == 'forbidden' }
    end
  end

  # --------------------------------------------------------------- factories

  def self.define_factories
    return if @factories_defined

    @factories_defined = true
    define_factory_bot
    define_bakery
  end

  def self.define_factory_bot
    FactoryBot.define do
      factory :flat_item, class: 'PerfBench::FlatItem' do
        name { 'Widget' }
        position { 1 }
      end

      factory :account, class: 'PerfBench::Account' do
        sequence(:email) { |n| "user#{n}@example.com" }
        sequence(:username) { |n| "user_#{n}" }
        status { 'active' }
        role { :member }
      end

      factory :author, class: 'PerfBench::Author' do
        name { 'Ada' }
      end
      factory :post, class: 'PerfBench::Post' do
        title { 'Title' }
        author
      end
      factory :comment, class: 'PerfBench::Comment' do
        body { 'Nice post' }
        post
      end

      factory :book, class: 'PerfBench::Book' do
        title { 'Dune' }
        library
      end
      # The has_many recipe factory_bot's guide recommends.
      factory :library, class: 'PerfBench::Library' do
        name { 'Central' }

        factory :library_with_books do
          transient { books_count { 3 } }
          books { Array.new(books_count) { association(:book, library: instance) } }
        end
      end

      factory :profile, class: 'PerfBench::Profile' do
        name { 'Grace' }
        bio { 'Hello' }
      end

      factory :note, class: 'PerfBench::Note' do
        title { 'A note' }
      end
    end
  end

  # The same values factory_bot sets, declared as a FactoryBakery definition,
  # under a symbol so `bake(Account)` stays definition-free.
  def self.define_bakery
    counter = 0
    FactoryBakery.define(:defined_account, klass: Account) do
      email { "user#{counter += 1}@example.com" }
      username { "user_#{counter}" }
      status { 'active' }
      role { 'member' }
    end

    # The same graphs as the automatic chain, with each edge declared inside
    # the definition (as factory_bot's `author` / `post` lines do).
    FactoryBakery.define(:declared_author, klass: Author) { name { 'Ada' } }
    FactoryBakery.define(:declared_post, klass: Post) do
      title { 'Title' }
      association :author, factory: :declared_author
    end
    FactoryBakery.define(:declared_comment, klass: Comment) do
      body { 'Nice post' }
      association :post, factory: :declared_post
    end
  end

  # -------------------------------------------------------------- scenarios

  Scenario = Struct.new(:key, :label, :bakery, :factory_bot, :settings, keyword_init: true)

  def self.scenarios
    fb = FactoryBakery
    bot = FactoryBot
    [
      Scenario.new(key: :flat_build, label: 'flat: bake vs build',
                   bakery: -> { fb.bake(FlatItem) }, factory_bot: -> { bot.build(:flat_item) }),
      Scenario.new(key: :flat_create, label: 'flat: bake! vs create',
                   bakery: -> { fb.bake!(FlatItem) }, factory_bot: -> { bot.create(:flat_item) }),
      Scenario.new(key: :validated_build, label: 'validated: bake vs build',
                   bakery: -> { fb.bake(Account) }, factory_bot: -> { bot.build(:account) }),
      Scenario.new(key: :validated_create, label: 'validated: bake! vs create',
                   bakery: -> { fb.bake!(Account) }, factory_bot: -> { bot.create(:account) }),
      Scenario.new(key: :defined_build, label: 'validated + definition: bake vs build',
                   bakery: -> { fb.bake(:defined_account) }, factory_bot: -> { bot.build(:account) }),
      Scenario.new(key: :defined_create, label: 'validated + definition: bake! vs create',
                   bakery: -> { fb.bake!(:defined_account) }, factory_bot: -> { bot.create(:account) }),
      Scenario.new(key: :chain_build, label: 'belongs_to chain x3 (required_only): bake vs build',
                   bakery: -> { fb.bake(Comment) }, factory_bot: -> { bot.build(:comment) },
                   settings: { mode: :required_only }),
      Scenario.new(key: :chain_create, label: 'belongs_to chain x3 (required_only): bake! vs create',
                   bakery: -> { fb.bake!(Comment) }, factory_bot: -> { bot.create(:comment) },
                   settings: { mode: :required_only }),
      Scenario.new(key: :declared_post_build, label: 'declared belongs_to x1: bake vs build',
                   bakery: -> { fb.bake(:declared_post) }, factory_bot: -> { bot.build(:post) },
                   settings: { mode: :required_only }),
      Scenario.new(key: :declared_post_create, label: 'declared belongs_to x1: bake! vs create',
                   bakery: -> { fb.bake!(:declared_post) }, factory_bot: -> { bot.create(:post) },
                   settings: { mode: :required_only }),
      Scenario.new(key: :declared_chain_build, label: 'declared belongs_to chain x3: bake vs build',
                   bakery: -> { fb.bake(:declared_comment) }, factory_bot: -> { bot.build(:comment) },
                   settings: { mode: :required_only }),
      Scenario.new(key: :declared_chain_create, label: 'declared belongs_to chain x3: bake! vs create',
                   bakery: -> { fb.bake!(:declared_comment) }, factory_bot: -> { bot.create(:comment) },
                   settings: { mode: :required_only }),
      Scenario.new(key: :has_many_build, label: 'has_many x3 (:all): bake vs build',
                   bakery: -> { fb.bake(Library) }, factory_bot: -> { bot.build(:library_with_books) },
                   settings: { mode: :all, default_count: 3 }),
      Scenario.new(key: :has_many_create, label: 'has_many x3 (:all): bake! vs create',
                   bakery: -> { fb.bake!(Library) }, factory_bot: -> { bot.create(:library_with_books) },
                   settings: { mode: :all, default_count: 3 }),
      Scenario.new(key: :probe_build, label: 'custom validation, probe only: bake vs build',
                   bakery: -> { fb.bake(Note) }, factory_bot: -> { bot.build(:note) }),
      Scenario.new(key: :fallback_build, label: 'custom validation, fallback rebuild: bake vs build',
                   bakery: -> { fb.bake(Profile) }, factory_bot: -> { bot.build(:profile) }),
      Scenario.new(key: :fallback_create, label: 'custom validation, fallback rebuild: bake! vs create',
                   bakery: -> { fb.bake!(Profile) }, factory_bot: -> { bot.create(:profile) })
    ]
  end

  def self.select_scenarios
    only = ENV.fetch('PERF_ONLY', '').split(',').map(&:strip).reject(&:empty?).map(&:to_sym)
    only.empty? ? scenarios : scenarios.select { |scenario| only.include?(scenario.key) }
  end

  # Each call runs the way a transactional test suite runs it: inside an
  # outer transaction that is rolled back, so tables never grow and both
  # libraries pay the same isolation cost. It is opened exactly the way
  # Rails' transactional fixtures open theirs: eager and non-joinable. That
  # matters: inside a clean joinable transaction Rails turns a nested
  # transaction into a free RestartParentTransaction, whereas under the
  # fixture transaction every `save!` and every `requires_new` block becomes
  # a real SAVEPOINT / RELEASE, for both libraries.
  def self.in_rolled_back_transaction
    connection = ActiveRecord::Base.connection
    connection.begin_transaction(joinable: false, _lazy: false)
    yield
  ensure
    connection.rollback_transaction
  end

  # Associations plugin settings for the scenario (mode :none when it sets
  # none, so flat and validated scenarios measure core alone).
  def self.with_settings(scenario, &block)
    FactoryBakery::Associations.with(**(scenario.settings || { mode: :none }), &block)
  end

  # Deterministic per-call shape: SQL statements by kind and `valid?` calls,
  # read from one warm call.
  def self.call_shape(callable)
    in_rolled_back_transaction { callable.call }
    self.valid_calls = 0
    counter = QueryCounter.new.measure { in_rolled_back_transaction { callable.call } }
    { sql: counter.counts.dup, valid: valid_calls }
  end

  # Mean allocations per call over a warm loop with GC disabled.
  def self.allocations_per_call(callable, iterations = 200)
    in_rolled_back_transaction { callable.call }
    GC.start
    GC.disable
    before = GC.stat(:total_allocated_objects)
    iterations.times { in_rolled_back_transaction { callable.call } }
    (GC.stat(:total_allocated_objects) - before) / iterations.to_f
  ensure
    GC.enable
  end
end
# rubocop:enable Metrics/ModuleLength, Metrics/MethodLength, Metrics/AbcSize
# rubocop:enable Style/Documentation
