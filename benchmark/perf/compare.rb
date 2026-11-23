# frozen_string_literal: true

# FactoryBakery vs factory_bot on one schema with equivalent factories.
#
#   bundle exec ruby benchmark/perf/compare.rb
#   DATABASE_URL=postgres://localhost/factory_bakery_perf bundle exec ruby benchmark/perf/compare.rb
#
# Env: PERF_TIME (seconds per entry, default 2), PERF_WARMUP (default 1),
# PERF_ONLY (comma-separated scenario keys, see support.rb).
#
# Prints, per scenario: iterations/sec for both libraries and their ratio
# (benchmark-ips), SQL statements and `valid?` calls per call, and
# allocations per call. Output is a Markdown table.

# rubocop:disable Metrics/AbcSize

require_relative 'support'
require 'benchmark/ips'

module PerfBench
  # Runs every scenario for both libraries and prints the Markdown tables.
  module Compare
    module_function

    def run
      PerfBench.setup_database!
      PerfBench.define_factories
      time = Float(ENV.fetch('PERF_TIME', '2'))
      warmup = Float(ENV.fetch('PERF_WARMUP', '1'))

      rows = PerfBench.select_scenarios.map do |scenario|
        warn "-> #{scenario.label}"
        PerfBench.with_settings(scenario) { measure(scenario, time, warmup) }
      end

      print_header(time, warmup)
      print_speed(rows)
      print_shape(rows)
    end

    def measure(scenario, time, warmup)
      calls = { bakery: scenario.bakery, factory_bot: scenario.factory_bot }
      shapes = calls.transform_values { |callable| PerfBench.call_shape(callable) }
      allocations = calls.transform_values { |callable| PerfBench.allocations_per_call(callable) }
      report = Benchmark.ips(quiet: true) do |x|
        x.config(time: time, warmup: warmup)
        calls.each { |name, callable| x.report(name.to_s) { PerfBench.in_rolled_back_transaction(&callable) } }
      end
      ips = report.entries.to_h { |entry| [entry.label.to_sym, entry] }
      { scenario: scenario, shapes: shapes, allocations: allocations, ips: ips }
    end

    def print_header(time, warmup)
      puts "# FactoryBakery vs factory_bot (#{PerfBench.database_label})"
      puts
      puts "Ruby #{RUBY_VERSION}, ActiveRecord #{ActiveRecord::VERSION::STRING}, " \
           "factory_bot #{FactoryBot::VERSION}, benchmark-ips #{time}s/#{warmup}s warmup per entry."
      puts 'Each call runs inside a rolled-back transaction (transactional-test style).'
      puts
    end

    def print_speed(rows)
      puts '| scenario | FactoryBakery i/s | µs/call | factory_bot i/s | µs/call | slower by |'
      puts '|---|---:|---:|---:|---:|---:|'
      rows.each do |row|
        bakery = row[:ips][:bakery]
        bot = row[:ips][:factory_bot]
        ratio = bot.stats.central_tendency / bakery.stats.central_tendency
        puts "| #{row[:scenario].label} | #{ips(bakery)} | #{micros(bakery)} | #{ips(bot)} | #{micros(bot)} | " \
             "#{format('%.2fx', ratio)} |"
      end
      puts
    end

    def print_shape(rows)
      puts '| scenario | lib | SELECT | INSERT | UPDATE | SAVEPOINT+RELEASE | ROLLBACK | other | valid? | allocs |'
      puts '|---|---|---:|---:|---:|---:|---:|---:|---:|---:|'
      rows.each do |row|
        row[:shapes].each do |lib, shape|
          sql = shape[:sql]
          other = sql.reject { |kind, _| %i[select insert update savepoint rollback].include?(kind) }.values.sum
          puts "| #{row[:scenario].label} | #{lib} | #{sql[:select]} | #{sql[:insert]} | #{sql[:update]} | " \
               "#{sql[:savepoint]} | #{sql[:rollback]} | #{other} | #{shape[:valid]} | " \
               "#{row[:allocations][lib].round} |"
        end
      end
    end

    def ips(entry)
      value = entry.stats.central_tendency
      error = entry.stats.error_percentage
      format('%<v>.0f ±%<e>.1f%%', v: value, e: error)
    end

    def micros(entry)
      format('%.1f', 1_000_000.0 / entry.stats.central_tendency)
    end
  end
end

PerfBench::Compare.run if $PROGRAM_NAME == __FILE__
# rubocop:enable Metrics/AbcSize
