# frozen_string_literal: true

# Profiles one FactoryBakery scenario from support.rb.
#
#   bundle exec ruby benchmark/perf/profile.rb validated_build [stackprof|vernier|memory|all]
#
# Env: PERF_ITERATIONS (default 3000), PERF_OUT (default tmp/perf).
# Writes stackprof dumps (wall and object mode) and a text summary, a vernier
# profile (open it at https://vernier.prof), and a memory_profiler report.

# rubocop:disable Metrics/AbcSize

require_relative 'support'
require 'fileutils'

module PerfBench
  # Steady-state profiles of one FactoryBakery scenario.
  module Profiler
    module_function

    def run(key, tool)
      PerfBench.setup_database!
      PerfBench.define_factories
      scenario = PerfBench.scenarios.find { |candidate| candidate.key == key.to_sym } ||
                 abort("unknown scenario #{key}; one of #{PerfBench.scenarios.map(&:key).join(', ')}")
      out = ENV.fetch('PERF_OUT', 'tmp/perf')
      FileUtils.mkdir_p(out)
      iterations = Integer(ENV.fetch('PERF_ITERATIONS', '3000'))
      # Profilers may yield their own argument to the block; ignore it.
      work = proc { iterations.times { PerfBench.in_rolled_back_transaction(&scenario.bakery) } }

      PerfBench.with_settings(scenario) do
        # Warm every per-class cache first: the profile is of steady state.
        200.times { PerfBench.in_rolled_back_transaction(&scenario.bakery) }
        tools = tool == 'all' ? %w[stackprof vernier memory] : [tool]
        tools.each { |name| send("profile_#{name}", work, File.join(out, key.to_s)) }
      end
    end

    def profile_stackprof(work, prefix)
      require 'stackprof'
      { wall: 100, object: 1 }.each do |mode, interval|
        StackProf.run(mode: mode, interval: interval, raw: true, out: "#{prefix}-#{mode}.dump", &work)
        # The dump was written by StackProf a line above, in this process.
        report = StackProf::Report.new(Marshal.load(File.binread("#{prefix}-#{mode}.dump"))) # rubocop:disable Security/MarshalLoad
        File.open("#{prefix}-#{mode}.txt", 'w') { |file| report.print_text(false, 60, nil, nil, nil, nil, file) }
        File.open("#{prefix}-#{mode}-cumulative.txt", 'w') do |file|
          report.print_text(true, 80, nil, nil, nil, nil, file)
        end
        warn "stackprof #{mode}: #{prefix}-#{mode}.txt"
      end
    end

    def profile_vernier(work, prefix)
      require 'vernier'
      Vernier.profile(out: "#{prefix}-vernier.json", allocation_interval: 100, &work)
      warn "vernier: #{prefix}-vernier.json"
    end

    def profile_memory(work, prefix)
      require 'memory_profiler'
      report = MemoryProfiler.report(top: 40, &work)
      report.pretty_print(to_file: "#{prefix}-memory.txt", scale_bytes: true, normalize_paths: true)
      warn "memory_profiler: #{prefix}-memory.txt"
    end
  end
end

PerfBench::Profiler.run(ARGV.fetch(0, 'validated_build'), ARGV.fetch(1, 'all')) if $PROGRAM_NAME == __FILE__
# rubocop:enable Metrics/AbcSize
