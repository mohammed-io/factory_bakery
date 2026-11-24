#!/usr/bin/env ruby
# frozen_string_literal: true

# Judges a test diff: every changed line must be a factory-call rename.
#
# Usage (from the migration worktree):
#   git diff -U0 --no-color --no-ext-diff --src-prefix=a/ --dst-prefix=b/ HEAD -- spec test factories factories.rb | ruby check_renames.rb
#
# Read-only. It reads a unified diff from stdin and prints a report. Exit
# status is 1 only when a FAIL appears.
#
# FAIL (exit 1): a changed line that is not a factory-call change (a
#                non-factory edit), a build_stubbed / build_stubbed_list /
#                build_stubbed_pair call, paren-less or not (a documented
#                blocker), a hunk whose removed and added line counts differ,
#                an edited or moved tracked factory definition file
#                (spec/factories.rb, test/factories.rb, factories.rb, or a
#                file under spec/factories/, test/factories/ or factories/),
#                or input the script cannot parse.
# REVIEW (exit 0): everything else, and a human reads each one: every call
#                split over lines (parentheses unbalanced on the changed
#                line, a target on its own line, a lone `)` becoming a `}`),
#                a paren-less call (`create :post`, `build :user, name: 'x'`,
#                `create_list :post, 3`, `attributes_for :post`), a Machinist
#                or Fabrication or hand-rolled form (`User.make`,
#                `User.make!`, `User.plan`, `Post.create!(attrs)`,
#                `Post.new(attrs)`, `Fabricate(...)`), a call that keeps a
#                receiver, a changed target or namespace, a changed verb or
#                count, a changed literal or argument, two calls on one
#                line, a scalar call that becomes Array.new(n), a
#                whitespace-only change, a binary file
#                (`REVIEW <path>: binary file changed`), a file mode change
#                (`REVIEW <path>: file mode changed`).
#                Action: a changed verb or count is never fine -- restore the
#                mapped verb (create -> bake!, build -> bake) and the count.
#                A changed target is fine only when it is the class the old
#                factory built (namespaced class, quoted symbol's class,
#                acronym class); otherwise restore it. For a split call or
#                anything else: if only the call's spelling changed, fine;
#                otherwise revert that line.
# LIST (exit 0): a create_list / build_list / create_pair / build_pair
#                rename to Array.new(n) { ... } whose count, verb, target and
#                arguments are unchanged (create_pair / build_pair mean 2).
# SUPPORT FILE (exit 0): a change under spec|test/(bakery|support), or in
#                spec/rails_helper.rb, spec/spec_helper.rb,
#                test/test_helper.rb. Listed, never judged. The factory-file
#                check runs first: a factory definition moved into
#                spec/bakery still FAILs.
# NEW FILE / DELETED FILE / RENAMED FILE (exit 0): file events a rename does
#                not produce, except the final deletion commit. Listed, never
#                judged here. A copy prints `NEW FILE <to> (copy of <from>)`.
#                A rename with content edits lists its edited lines. A human
#                looks at each. Read `git diff --stat` and `--summary` for
#                binary and mode changes.
#
# The CLEAN whitelist, judged per removed/added pair (exactly one call per
# line):
#   create(:x)         -> FactoryBakery.bake!(X)   (or .bake!(X))
#   build(:x)          -> FactoryBakery.bake(X)    (or .bake(X))
#   attributes_for(:x) -> bakery_attributes_for(X)
# The new spelling is a bare bake!(X) via FactoryBakery::Methods, or
# FactoryBakery.bake!(X): a call that keeps a receiver (helper.bake!(User))
# is REVIEW. The target stays the same symbol, or becomes the class the
# factory name camelizes to (:admin_post -> AdminPost; per segment,
# w[0].upcase + rest). The text before the call and after the target must be
# unchanged with leading/trailing whitespace ignored only -- a space changed
# inside a literal is a change -- and the matched call's parentheses must be
# balanced on both changed lines (an unbalanced line is a split call:
# REVIEW).
#
# The accept-set is the allowlist shape itself; a project-local helper
# coincidentally named create or build is silent.

SUPPORT_PATH = %r{\A(?:spec|test)/(?:bakery|support)/}.freeze
SUPPORT_FILES = %w[spec/rails_helper.rb spec/spec_helper.rb test/test_helper.rb].freeze
FACTORY_DIR = %r{\A(?:(?:spec/|test/)?factories\.rb\z|(?:spec/factories|test/factories|factories)/)}.freeze

OLD_CALL = /(?<![.\w])(?:FactoryBot\.)?(create|build|attributes_for)\(\s*:(\w+)/
NEW_CALL = /(?<![.\w])(?:FactoryBakery\.)?(bake!?|bakery_attributes_for)\(\s*([A-Z][\w:]*|:\w+)/
OLD_TOKEN = /
  (?<![.\w])(?:FactoryBot\.)?(?:create|build|attributes_for)(?:_list|_pair)?(?:\(|\s+:)
  | (?<![.\w])build_stubbed(?:_list|_pair)?(?:\(|\s+:)
  | \bFabricate\b
  | \.make!?\b
  | \.plan\b
/x
NEW_TOKEN = /
  (?<![.\w])(?:FactoryBakery\.)?bake!?(?:\(|\s+:)
  | (?<![.\w])bakery_attributes_for(?:\(|\s+:)
  | (?<![.\w])attributes_for(?:\(|\s+:)
/x
RECEIVER_OLD_CALL = /
  (?<!FactoryBot)\.(?:create|build|attributes_for)(?:_list|_pair)?(?:\(|\s+:)
  | \.create!\(
  | (?<!Array)\.new\(
  | \.make!?\b
  | \.plan\b
/x
RECEIVER_NEW_CALL = /(?<!FactoryBakery)\.(?:bake!?|bakery_attributes_for)\(/
BUILD_STUBBED = /\bbuild_stubbed(?:_list|_pair)?(?:\(|\s+:)/
OLD_LIST = /(?<![.\w])(?:FactoryBot\.)?(create|build)_(list|pair)\(\s*:(\w+)\s*(?:,\s*(\d+))?/
NEW_WRAPPER = /(?<![.\w])Array\.new\(\s*(\d+)\s*\)\s*\{\s*/
OLD_VERBS = { 'create' => 'bake!', 'build' => 'bake', 'attributes_for' => 'bakery_attributes_for' }.freeze
LIST_VERBS = { 'create' => 'bake!', 'build' => 'bake' }.freeze
SPLIT_OPENER = /(?<![.\w])(?:FactoryBot\.)?(?:create|build|attributes_for)\(\s*\z/
LIST_SPLIT_OPENER = /(?<![.\w])(?:FactoryBot\.)?(?:create|build)_(?:list|pair)\(\s*\z/
TARGET_ONLY_OLD = /\A\s*:(?:\w|")/
TARGET_ONLY_NEW = /\A\s*(?:[A-Z][\w:]*|:(?:\w+|"))\s*[,)]/
SPLIT_NOTE = 'split call: check by hand'
BLOCKER_NOTE = 'build_stubbed has no FactoryBakery equivalent (blocker)'
RECEIVER_NOTE = 'call keeps a receiver: the accepted spellings are a bare bake!(X) via FactoryBakery::Methods or FactoryBakery.bake!(X)'
UNKNOWN_FILE = '<unknown>'
ESC = { 'n' => "\n", 't' => "\t", 'r' => "\r", '"' => '"', '\\' => '\\' }.freeze

module DiffPaths
  module_function

  # "a/spec/models/caf\303\251_spec.rb" -> spec/models/café_spec.rb.
  # One byte-oriented pass: octal escapes become raw bytes, \\ stays a
  # literal backslash (so \\303 is a backslash followed by 303, never a
  # byte), then the bytes are read as UTF-8 and scrubbed.
  def clean(token)
    path = token.strip
    path = path.delete_prefix('"').delete_suffix('"') if path.start_with?('"')
    path = path.delete_prefix('a/').delete_prefix('b/')
    return path unless path.include?('\\')

    path.b.gsub(/\\(?:([0-7]{3})|([ntr"\\]))/n) { Regexp.last_match(1) ? Regexp.last_match(1).to_i(8).chr : ESC[Regexp.last_match(2)] }
        .force_encoding(Encoding::UTF_8)
        .scrub
  end
end

class RenameCheck
  attr_reader :fails

  def initialize
    @fails = 0
    @reviews = 0
    @files = 0
    @pairs = 0
  end

  def count_file
    @files += 1
  end

  def judged?(file)
    !file.nil? && file[:event] == :edit && !factory_file?(file) && !support_file?(file)
  end

  def review_line(message)
    @reviews += 1
    puts "REVIEW #{message}"
  end

  def report_event(file)
    return if file.nil? || file[:reported]

    file[:reported] = true
    label = file[:event] == :deleted ? file[:old] : (file[:new] || file[:old])
    if factory_file?(file)
      case file[:event]
      when :edit
        @fails += 1
        puts "FAIL   #{label}: edited factory definition (never touch the old factories)"
      when :rename
        @fails += 1
        puts "FAIL   #{file[:old]} -> #{file[:new]}: moved factory definition (never touch the old factories)"
      else
        event_line(file, label)
      end
      return
    end
    if support_file?(file)
      shown = file[:event] == :rename ? "#{file[:old]} -> #{file[:new]}" : label
      puts "SUPPORT FILE #{shown}"
      return
    end
    event_line(file, label)
  end

  def list_moved_lines(file, removed, added)
    return if removed.empty? && added.empty?

    @reviews += 1
    removed.each { |l| puts "         - #{l[1..].to_s.strip}" }
    added.each { |l| puts "         + #{l[1..].to_s.strip}" }
  end

  def judge_hunk(file, removed, added)
    if file[:unparsable]
      @fails += 1
      puts "FAIL   #{file[:new]}: could not parse"
      return
    end

    @pairs += [removed.length, added.length].max
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
    if @files.zero?
      puts '0 files, 0 line pairs: nothing to check (wrong directory, pathspec or SHA?)'
    else
      puts "\nsummary: #{@files} files, #{@pairs} line pairs, #{@fails} fail, #{@reviews} review"
    end
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

  def event_line(file, label)
    case file[:event]
    when :new then puts "NEW FILE     #{label}"
    when :deleted then puts "DELETED FILE #{label}"
    when :rename then puts "RENAMED FILE #{file[:old]} -> #{file[:new]}"
    when :copy then puts "NEW FILE     #{file[:new]} (copy of #{file[:old]})"
    end
  end

  # One whitelist for CLEAN. Anything it does not accept is REVIEW (or FAIL
  # for build_stubbed, a non-factory edit, an unreadable hunk or a factory
  # file, judged before or beside this).
  def judge_pair(o, n)
    return [:fail, BLOCKER_NOTE] if o.match?(BUILD_STUBBED)

    if o.match?(SPLIT_OPENER) || o.match?(LIST_SPLIT_OPENER)
      return [:review, SPLIT_NOTE]
    end

    return [:review, nil] if o.strip == ')' && n.strip == '}'

    if o.match?(TARGET_ONLY_OLD)
      return [:review, n.match?(TARGET_ONLY_NEW) ? SPLIT_NOTE : nil]
    end

    if o.match?(RECEIVER_OLD_CALL) || n.match?(RECEIVER_NEW_CALL)
      return [:review, RECEIVER_NOTE]
    end

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
    return false unless balanced?(o) && balanced?(n)

    om = old_calls[0]
    nm = new_calls[0]

    old_tokens = matches(o, OLD_TOKEN)
    return false unless old_tokens.size == 1 && old_tokens[0].begin(0) == om.begin(0)
    new_tokens = matches(n, NEW_TOKEN)
    return false unless new_tokens.size == 1 && new_tokens[0].begin(0) == nm.begin(0)

    return false unless OLD_VERBS[om[1]] == nm[1]
    return false unless targets_match?(om[2], nm[2])

    o[0...om.begin(0)].strip == n[0...nm.begin(0)].strip &&
      o[om.end(0)..].strip == n[nm.end(0)..].strip
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

    o[0...om.begin(0)].strip == stripped[0...im.begin(0)].strip &&
      o[om.end(0)..].strip == stripped[im.end(0)..].strip ? :list : :review
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

  def balanced?(line)
    line.count('(') == line.count(')')
  end

  def flat(str)
    str.to_s.gsub(/\s+/, '')
  end
end

$stdin.set_encoding(Encoding::UTF_8)

checker = RenameCheck.new
state = { file: nil, removed: [], added: [], in_hunk: false, rem_old: 0, rem_new: 0 }

flush_hunk = lambda do
  next if state[:removed].empty? && state[:added].empty?

  if checker.judged?(state[:file])
    checker.judge_hunk(state[:file], state[:removed], state[:added])
  elsif state[:file] && %i[rename copy].include?(state[:file][:event])
    checker.list_moved_lines(state[:file], state[:removed], state[:added])
  end
  state[:removed] = []
  state[:added] = []
end

finish_file = lambda do
  flush_hunk.call
  checker.report_event(state[:file]) if state[:file] && !state[:file][:reported]
  state = { file: nil, removed: [], added: [], in_hunk: false, rem_old: 0, rem_new: 0 }
end

# Hunk content while the declared @@ counts are not exhausted: -, +, space
# and backslash lines are hunk lines even when they look like headers
# (a removed "-- old comment" arrives as "--- old comment").
consume_hunk_line = lambda do |line|
  case line[0]
  when '+' then state[:added] << line
  when '-' then state[:removed] << line
  end
  state[:rem_old] -= 1 if line[0] == '-' || line[0] == ' '
  state[:rem_new] -= 1 if line[0] == '+' || line[0] == ' '
  state[:in_hunk] = false if state[:rem_old] <= 0 && state[:rem_new] <= 0
end

$stdin.each_line(chomp: true) do |raw|
  line = raw.scrub
  if state[:in_hunk] && (state[:rem_old].positive? || state[:rem_new].positive?) && line.match?(/\A[-+ \\]/)
    consume_hunk_line.call(line)
    next
  end
  case line
  when /\Adiff --git /
    finish_file.call
    checker.count_file
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
  when /\A(?:old|new) mode /
    if state[:file] && !state[:in_hunk] && !state[:file][:reported]
      checker.review_line("#{state[:file][:new] || state[:file][:old]}: file mode changed")
      state[:file][:reported] = true
    end
  when /\ABinary files .+ differ/, /\AGIT binary patch/
    if state[:file] && !state[:file][:reported]
      checker.review_line("#{state[:file][:new] || state[:file][:old]}: binary file changed")
      state[:file][:reported] = true
    end
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
  when /\Acopy from /
    if state[:file] && !state[:in_hunk]
      state[:file][:old] = DiffPaths.clean(line.delete_prefix('copy from '))
      state[:file][:event] = :copy
    end
  when /\Acopy to /
    if state[:file] && !state[:in_hunk]
      state[:file][:new] = DiffPaths.clean(line.delete_prefix('copy to '))
      state[:file][:event] = :copy
    end
  when /\A--- /
    body = line[4..].to_s
    if !state[:in_hunk] && state[:file] && state[:file][:plain] &&
       (state[:file][:new] || state[:removed].any? || state[:added].any?)
      finish_file.call
    end
    unless state[:file]
      checker.count_file
      state[:file] = { old: nil, new: nil, event: :edit, reported: false, plain: true }
    end
    state[:file][:old] = DiffPaths.clean(body) if !state[:in_hunk] && body.strip != '/dev/null'
  when /\A\+\+\+ /
    body = line[4..].to_s
    unless state[:file]
      checker.count_file
      state[:file] = { old: nil, new: nil, event: :edit, reported: false, plain: true }
    end
    state[:file][:new] = DiffPaths.clean(body) if !state[:in_hunk] && body.strip != '/dev/null'
  when /\A@@/
    flush_hunk.call
    unless state[:file]
      checker.count_file
      state[:file] = { old: UNKNOWN_FILE, new: UNKNOWN_FILE, event: :edit, reported: false, unparsable: true }
    end
    checker.report_event(state[:file]) unless state[:file][:reported]
    state[:file][:reported] = true
    counts = line.match(/\A@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@/)
    state[:rem_old] = counts ? (counts[2] || counts[1]).to_i : Float::INFINITY
    state[:rem_new] = counts ? (counts[4] || counts[3]).to_i : Float::INFINITY
    state[:in_hunk] = true
  end
end
finish_file.call

checker.summary
exit(checker.fails.zero? ? 0 : 1)
