#!/usr/bin/env ruby
# frozen_string_literal: true

# Judges a test diff: every changed line must be a factory-call rename.
#
# Usage (from the migration worktree):
#   git diff -U0 --no-color --no-ext-diff --src-prefix=a/ --dst-prefix=b/ HEAD -- spec test | ruby check_renames.rb
#
# Read-only. It reads a unified diff from stdin and prints a report. Exit
# status is 1 only when a FAIL appears.
#
# FAIL (exit 1): a changed line that is not a factory-call change (a
#                non-factory edit), a build_stubbed / build_stubbed_list /
#                build_stubbed_pair call (a documented blocker), a hunk whose
#                removed and added line counts differ, or an edited tracked
#                file under spec/factories, test/factories or factories/
#                (never touch the old factories).
# REVIEW (exit 0): anything the whitelist does not accept, and a human reads
#                each one: every call split over lines, a changed target or
#                namespace, a changed verb or count, a changed literal or
#                argument, two calls on one line, a scalar call that becomes
#                Array.new(n), a whitespace-only change.
#                Action: a changed verb or count is never fine -- restore the
#                mapped verb (create -> bake!, build -> bake) and the count.
#                A changed target is fine only when it is the class the old
#                factory built (namespaced class, quoted symbol's class,
#                acronym class); otherwise restore it. For a split call or
#                anything else: if only the call's spelling changed, fine;
#                otherwise revert that line.
# LIST (exit 0): a create_list / build_list / *_pair rename to
#                Array.new(n) { ... } whose count, verb, target and arguments
#                are unchanged (create_pair / build_pair mean 2).
# SUPPORT FILE (exit 0): a change under spec|test/(bakery|support), or in
#                spec/rails_helper.rb, spec/spec_helper.rb,
#                test/test_helper.rb. Listed, never judged.
# NEW FILE / DELETED FILE / RENAMED FILE (exit 0): file events a rename does
#                not produce, except the final deletion commit. Listed, never
#                judged here. A human looks at each.
#
# The CLEAN whitelist, judged per removed/added pair (exactly one call per
# line):
#   create(:x)         -> FactoryBakery.bake!(X)   (or .bake!(X))
#   build(:x)          -> FactoryBakery.bake(X)    (or .bake(X))
#   attributes_for(:x) -> bakery_attributes_for(X)
# The target stays the same symbol, or becomes the class the factory name
# camelizes to (:admin_post -> AdminPost; per segment, w[0].upcase + rest).
# The text before the call and after the target must be unchanged (whitespace
# ignored). That comparison is also what rejects an Array.new(n) wrapper
# appearing on one side only; a wrapper already present on both lines with
# the same text stays clean.

SUPPORT_PATH = %r{\A(?:spec|test)/(?:bakery|support)/}.freeze
SUPPORT_FILES = %w[spec/rails_helper.rb spec/spec_helper.rb test/test_helper.rb].freeze
FACTORY_DIR = %r{\A(?:spec/factories|test/factories|factories)/}.freeze

OLD_CALL = /\b(?:FactoryBot\.)?(create|build|attributes_for)\(\s*:(\w+)/
NEW_CALL = /\b(?:FactoryBakery\.)?(bake!?|bakery_attributes_for)\(\s*([A-Z][\w:]*|:\w+)/
OLD_TOKEN = /\b(?:FactoryBot\.)?(?:create|build|attributes_for)(?:_list|_pair)?\(|\bbuild_stubbed(?:_list|_pair)?\(|\bFabricate\b|\.make!?\(|\.plan\(/
NEW_TOKEN = /\b(?:FactoryBakery\.)?bake!?\(|\bbakery_attributes_for\(|\battributes_for\(/
OLD_LIST = /\b(?:FactoryBot\.)?(create|build)_(list|pair)\(\s*:(\w+)\s*(?:,\s*(\d+))?/
NEW_WRAPPER = /\bArray\.new\(\s*(\d+)\s*\)\s*\{\s*/
OLD_VERBS = { 'create' => 'bake!', 'build' => 'bake', 'attributes_for' => 'bakery_attributes_for' }.freeze
LIST_VERBS = { 'create' => 'bake!', 'build' => 'bake' }.freeze
SPLIT_OPENER = /\b(?:FactoryBot\.)?(?:create|build|attributes_for)\(\s*\z/
TARGET_ONLY_OLD = /\A\s*:\w/
TARGET_ONLY_NEW = /\A\s*(?:[A-Z][\w:]*|:\w+)/
SPLIT_NOTE = 'split call: check by hand'

module DiffPaths
  module_function

  # "a/spec/models/caf\303\251_spec.rb" -> spec/models/café_spec.rb
  def clean(token)
    path = token.strip
    path = path.delete_prefix('"').delete_suffix('"') if path.start_with?('"')
    path = path.delete_prefix('a/').delete_prefix('b/')
    return path unless path.include?('\\')

    path.gsub(/\\([0-7]{3})/) { [$1.to_i(8)].pack('C').force_encoding(Encoding::UTF_8) }
        .gsub(/\\([ntr"\\])/) { { 'n' => "\n", 't' => "\t", 'r' => "\r", '"' => '"', '\\' => '\\' }[$1] }
        .scrub
  end
end

class RenameCheck
  attr_reader :fails

  def initialize
    @fails = 0
    @reviews = 0
  end

  def judged?(file)
    !file.nil? && file[:event] == :edit && !support_file?(file) && !factory_file?(file)
  end

  def report_event(file)
    return if file.nil?

    label = file[:event] == :deleted ? file[:old] : (file[:new] || file[:old])
    if support_file?(file)
      shown = file[:event] == :rename ? "#{file[:old]} -> #{file[:new]}" : label
      puts "SUPPORT FILE #{shown}"
      return
    end
    case file[:event]
    when :new then puts "NEW FILE     #{label}"
    when :deleted then puts "DELETED FILE #{label}"
    when :rename then puts "RENAMED FILE #{file[:old]} -> #{file[:new]}"
    when :edit
      return unless factory_file?(file)

      @fails += 1
      puts "FAIL   #{label}: edited factory definition (never touch the old factories)"
    end
  end

  def judge_hunk(file, removed, added)
    if removed.length != added.length
      @fails += 1
      puts "FAIL   #{file[:new]}: #{removed.length} line(s) removed, #{added.length} added (a rename is line for line)"
      removed.each { |l| puts "         #{l}" }
      added.each { |l| puts "         #{l}" }
      return
    end

    removed.zip(added).each do |old_line, new_line|
      verdict, note = judge_pair(old_line[1..].to_s, new_line[1..].to_s)
      case verdict
      when :fail
        @fails += 1
        puts "FAIL   #{file[:new]}: #{note}"
        puts "         - #{old_line[1..].to_s.strip}"
        puts "         + #{new_line[1..].to_s.strip}"
      when :review
        @reviews += 1
        puts "REVIEW #{file[:new]}"
        puts "         - #{old_line[1..].to_s.strip}"
        puts "         + #{new_line[1..].to_s.strip}"
        puts "         (#{note})" if note
      when :list
        puts "LIST   #{file[:new]}: #{old_line[1..].to_s.strip}  =>  #{new_line[1..].to_s.strip}"
      end
    end
  end

  def summary
    puts "\nsummary: #{@fails} fail, #{@reviews} review"
  end

  private

  def support_file?(file)
    [file[:old], file[:new]].compact.any? do |path|
      path.match?(SUPPORT_PATH) || SUPPORT_FILES.include?(path)
    end
  end

  def factory_file?(file)
    [file[:old], file[:new]].compact.any? { |path| path.match?(FACTORY_DIR) }
  end

  # One whitelist for CLEAN. Anything it does not accept is REVIEW (or FAIL
  # for build_stubbed and a non-factory edit, judged before this runs).
  def judge_pair(o, n)
    return [:fail, 'build_stubbed has no FactoryBakery equivalent (blocker)'] if o.match?(/\bbuild_stubbed(?:_list|_pair)?\(/)

    return [:review, SPLIT_NOTE] if o.match?(SPLIT_OPENER) || (o.match?(TARGET_ONLY_OLD) && n.match?(TARGET_ONLY_NEW))

    list = list_verdict(o, n)
    return [:list, nil] if list == :list
    return [:review, 'list/pair rename changed the count, verb, target or arguments'] if list == :review

    return [:clean, nil] if clean_rename?(o, n)

    unless o.match?(OLD_TOKEN) && n.match?(NEW_TOKEN)
      return [:review, 'whitespace-only change: check by hand'] if flat(o) == flat(n)

      return [:fail, 'non-factory change']
    end

    [:review, 'differs by more than the call spelling: verb, target or arguments changed']
  end

  def clean_rename?(o, n)
    old_calls = matches(o, OLD_CALL)
    new_calls = matches(n, NEW_CALL)
    return false unless old_calls.size == 1 && new_calls.size == 1

    om = old_calls[0]
    nm = new_calls[0]

    old_tokens = matches(o, OLD_TOKEN)
    return false unless old_tokens.size == 1 && old_tokens[0].begin(0) == om.begin(0)
    new_tokens = matches(n, NEW_TOKEN)
    return false unless new_tokens.size == 1 && new_tokens[0].begin(0) == nm.begin(0)

    return false unless OLD_VERBS[om[1]] == nm[1]
    return false unless targets_match?(om[2], nm[2])

    flat(o[0...om.begin(0)]) == flat(n[0...nm.begin(0)]) &&
      flat(o[om.end(0)..]) == flat(n[nm.end(0)..])
  end

  # create_list(:post, 3) -> Array.new(3) { FactoryBakery.bake!(Post) }.
  # A pair means 2. nil when the removed line is no list call at all.
  def list_verdict(o, n)
    lists = matches(o, OLD_LIST)
    return nil unless lists.size == 1 && matches(o, OLD_TOKEN).size == 1

    om = lists[0]
    old_count = om[2] == 'pair' ? '2' : om[4]
    wrappers = matches(n, NEW_WRAPPER)
    return :review if wrappers.size != 1
    return :review if old_count.nil? || old_count != wrappers[0][1]

    stripped = n.sub(NEW_WRAPPER, '').sub(/\}\s*\z/, '')
    inners = matches(stripped, NEW_CALL)
    return :review if inners.size != 1

    im = inners[0]
    return :review unless LIST_VERBS[om[1]] == im[1]
    return :review unless targets_match?(om[3], im[2])

    flat(o[0...om.begin(0)]) == flat(stripped[0...im.begin(0)]) &&
      flat(o[om.end(0)..]) == flat(stripped[im.end(0)..]) ? :list : :review
  end

  # The removed symbol target matches the added spelling exactly (:admin ->
  # :admin, :admin -> :Admin differs) or the class its name camelizes to
  # (:admin_post -> AdminPost). Namespaces compare exactly, so
  # :admin_post -> Admin::Post differs and a human decides.
  def targets_match?(old_word, new_token)
    return ":#{old_word}" == new_token if new_token.start_with?(':')

    camelize(old_word) == new_token
  end

  def camelize(word)
    word.split('::').map do |part|
      part.split('_').map { |w| w[0].to_s.upcase + w[1..].to_s }.join
    end.join('::')
  end

  def matches(str, regex)
    str.to_enum(:scan, regex).map { Regexp.last_match }
  end

  def flat(str)
    str.to_s.gsub(/\s+/, '')
  end
end

$stdin.set_encoding(Encoding::UTF_8)

checker = RenameCheck.new
state = { file: nil, removed: [], added: [], in_hunk: false }

flush_hunk = lambda do
  next if state[:removed].empty? && state[:added].empty?

  checker.judge_hunk(state[:file], state[:removed], state[:added]) if checker.judged?(state[:file])
  state[:removed] = []
  state[:added] = []
end

finish_file = lambda do
  flush_hunk.call
  checker.report_event(state[:file]) if state[:file] && !state[:file][:reported]
  state = { file: nil, removed: [], added: [], in_hunk: false }
end

$stdin.each_line(chomp: true) do |raw|
  line = raw.scrub
  case line
  when /\Adiff --git /
    finish_file.call
    rest = line.delete_prefix('diff --git ')
    split = rest.rindex(/ "b\//) || rest.rindex(/ b\//)
    state[:file] = {
      old: split ? DiffPaths.clean(rest[0...split]) : nil,
      new: split ? DiffPaths.clean(rest[split + 1..]) : DiffPaths.clean(rest),
      event: :edit, reported: false
    }
  when /\Anew file mode/
    state[:file][:event] = :new if state[:file] && !state[:in_hunk]
  when /\Adeleted file mode/
    state[:file][:event] = :deleted if state[:file] && !state[:in_hunk]
  when /\Arename from /
    if state[:file] && !state[:in_hunk]
      state[:file][:old] = DiffPaths.clean(line.delete_prefix('rename from '))
      state[:file][:event] = :rename
    end
  when /\Arename to /
    if state[:file] && !state[:in_hunk]
      state[:file][:new] = DiffPaths.clean(line.delete_prefix('rename to '))
      state[:file][:event] = :rename
    end
  when /\A--- /
    if state[:file] && !state[:in_hunk]
      body = line[4..].to_s
      state[:file][:old] = DiffPaths.clean(body) unless body.strip == '/dev/null'
    end
  when /\A\+\+\+ /
    if state[:file] && !state[:in_hunk]
      body = line[4..].to_s
      state[:file][:new] = DiffPaths.clean(body) unless body.strip == '/dev/null'
    end
  when /\A@@/
    flush_hunk.call
    state[:in_hunk] = true
    checker.report_event(state[:file]) unless state[:file][:reported]
    state[:file][:reported] = true
  when /\A-/
    state[:removed] << line unless state[:file] && %i[new deleted rename].include?(state[:file][:event])
  when /\A\+/
    state[:added] << line unless state[:file] && %i[new deleted rename].include?(state[:file][:event])
  end
end
finish_file.call

checker.summary
exit(checker.fails.zero? ? 0 : 1)
