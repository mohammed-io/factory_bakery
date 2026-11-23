#!/usr/bin/env ruby
# frozen_string_literal: true

# Checks that every changed line in the test files is a factory-call rename.
#
# Usage (from the migration worktree):
#   git diff -U0 --no-color HEAD -- spec test | ruby check_renames.rb              # uncommitted work
#   git diff -U0 --no-color <start-sha> HEAD -- spec test | ruby check_renames.rb  # the whole migration
#
# Read-only. It reads a unified diff from stdin and prints a report.
#
# FAIL  (exit 1): a changed line that is not a factory call, a build_stubbed
#                 call (a documented blocker), or a hunk whose removed and
#                 added line counts differ.
# REVIEW (exit 0): a verb that does not map (create -> bake, build -> bake!,
#                 attributes_for -> bakery_attributes_for), a changed bake
#                 target (a quoted symbol like :"admin/post", a namespaced
#                 class like Admin::Post reached from :admin_post, or a symbol
#                 whose case changed, like :admin -> :Admin, always reports),
#                 a changed list count, a scalar call that becomes
#                 Array.new(n), a *_pair that does not become Array.new(2),
#                 a changed list argument, or a pair whose text differs by
#                 more than the call. A human or the agent must look at each.
# LIST (exit 0): a create_list/build_list/*_pair rename to Array.new(n) whose
#                 count and arguments are unchanged (create_pair/build_pair
#                 mean 2).
# CLEAN on a call split over lines: an opener line (`create(` / `build(` at
#                 the end) whose verb maps to `FactoryBakery.bake!(` / `bake(`
#                 at the end, and a target alone on its line (`:post,` ->
#                 `Post,`) when it follows the camelize rule. Other
#                 continuation lines must be unchanged apart from indentation,
#                 and only count as continuations while a `(` is unbalanced.
# SUPPORT FILE: a helper, definition or suite-wiring file (spec|test bakery or
#                 support directories, spec/rails_helper.rb, spec/spec_helper.rb,
#                 test/test_helper.rb). Listed, never judged.
# NEW / DELETED FILE: listed, never judged here (the final deletion commit is
#                 checked by hand).

OLD_CALL = /\b(?:FactoryBot\.)?(?:create|build|build_stubbed|create_list|build_list|create_pair|build_pair|
                                  build_stubbed_list|attributes_for|Fabricate|Fabricate\.build|Fabricate\.times|
                                  Fabricate\.attributes_for)\b|\.make!?\b|\.plan\b/x
NEW_CALL = /FactoryBakery\.bake!?\(|\bbake!?\(|\bbakery_attributes_for\(|Array\.new\(\d+\)\s*\{/

# Every factory call on a line, with its target. Removed lines scan OLD_CALLS,
# added lines NEW_CALLS; the two lists of [verb, target] pairs must match.
OLD_CALLS = /\b(?:FactoryBot\.)?(create|build|attributes_for)(?:_list|_pair)?\(\s*:(\w+)/
NEW_CALLS = /\b(?:FactoryBakery\.)?(bake!?|bakery_attributes_for)\(\s*([A-Z][\w:]*|:\w+)/

# The FactoryBakery verb each removed factory_bot verb must map to.
OLD_VERBS = { 'create' => 'bake!', 'build' => 'bake', 'attributes_for' => 'bakery_attributes_for' }.freeze

# The factory_bot calls residue() normalizes away. create_pair/build_pair are
# not here: residue() pins them to a count of 2 before this runs.
OLD_RESIDUE = /\b(?:FactoryBot\.)?(?:create_list|build_list|
                               create|build|build_stubbed|attributes_for)\(\s*:\w+/x

# An opener line: the call name with its `(` at the end of the line, the
# target on the next line.
OPENER_OLD = /\b(?:FactoryBot\.)?(create|build)\(\s*\z/
OPENER_NEW = /\b(?:FactoryBakery\.)?(bake!?)\(\s*\z/

# The target alone on its line (a call split over at least three lines). The
# optional leading [-+] is the diff marker.
TARGET_ONLY_OLD = /\A[-+]?\s*:(\w+)\s*[,)]?\s*\z/
TARGET_ONLY_NEW = /\A[-+]?\s*([A-Z][\w:]*|:\w+)\s*[,)]?\s*\z/

# A helper or definition file, and the test-suite wiring files. Changes there
# are printed and never judged.
SUPPORT_PATH = %r{\A(?:(?:spec|test)/(?:bakery|support)/|spec/rails_helper\.rb\z|
                        spec/spec_helper\.rb\z|test/test_helper\.rb\z)}x

# Camelize a factory_bot target so :admin_post compares equal to AdminPost.
# Each segment keeps its case after the first letter is upcased: per word,
# w[0].to_s.upcase + w[1..].to_s (not capitalize, so inner capitals survive;
# not a bare w[0], so an empty segment from :a__b or :_admin raises nothing).
def camelize_target(token)
  token.delete_prefix(':').split('::').map do |part|
    part.split('_').map { |word| word[0].to_s.upcase + word[1..].to_s }.join
  end.join('::')
end

# A removed symbol target matches the added line's symbol spelling exactly
# (:admin stays :admin; :admin -> :Admin differs) or the class its name
# camelizes to (:admin_post -> AdminPost). Namespaces and case compare
# exactly, so :admin_post -> Admin::Post differs and a human decides.
def targets_match?(old_target, new_target)
  if new_target.start_with?(':')
    ":#{old_target}" == new_target
  else
    camelize_target(":#{old_target}") == new_target
  end
end

# An opener pair is clean when the verb maps: create( -> bake!( and
# build( -> bake( at the end of the line.
def opener_rename?(old_line, new_line)
  old = old_line.match(OPENER_OLD)
  new = new_line.match(OPENER_NEW)
  return false unless old && new

  new[1] == (old[1] == 'create' ? 'bake!' : 'bake')
end

# All factory calls on a removed line, as an ordered list of [mapped verb,
# raw target word] pairs. The target stays raw; targets_match? compares it
# against the added line's.
def old_calls(line)
  line.scan(OLD_CALLS).map { |verb, target| [OLD_VERBS.fetch(verb), target] }
end

# All factory calls on an added line, as an ordered list of [verb, target]
# pairs. Array.new(n) { wrappers are ignored here (the LIST branch checks the
# count); the verb and target stay as written.
def new_calls(line)
  body = line.sub(/\A\+/, '').gsub(/Array\.new\(\d+\)\s*\{\s*/, '')
  body.scan(NEW_CALLS)
end

# Quoted literals must carry over unchanged. residue ignores whitespace, so a
# changed literal word is caught here.
def literals(line)
  line.scan(/'[^']*'|"[^"]*"/)
end

# Reduces a line to what must stay identical across a rename. The list count
# and the pair's count of 2 are kept, so a changed count is visible; the LIST
# branch strips them again.
def residue(line)
  line.sub(/\A[-+]/, '')
      .gsub(/Array\.new\(\d+\)\s*\{\s*/, '')
      .gsub(/(\s*\})+\s*(?=\)|\z)/, '')
      # create_pair/build_pair mean count 2: pinned before the generic gsub,
      # so a pair that does not become Array.new(2) cannot compare clean.
      .gsub(/\b(?:FactoryBot\.)?(?:create|build)_pair\(\s*:\w+/, 'CALL(,2')
      .gsub(OLD_RESIDUE, 'CALL(')
      .gsub(/\b(?:FactoryBakery\.)?bake!?\(\s*(?:[A-Z][\w:]*|:\w+)/, 'CALL(')
      .gsub(/\bbakery_attributes_for\(\s*(?:[A-Z][\w:]*|:\w+)/, 'CALL(')
      .gsub(/CALL\(\s*/, 'CALL(')
      .gsub(/\s+/, '')
end

# residue with a pinned count stripped, so a list (or pair) rename compares by
# its arguments and traits alone. The old side carries the count inside the
# call (`CALL(,3,title:`), the new side loses it with Array.new, so the comma
# after CALL( goes too, on both sides.
def residue_without_count(line)
  residue(line).sub(/CALL\(,\d+(?=[,)])/, 'CALL(').sub(/CALL\(\,/, 'CALL(')
end

def review(file, old_line, new_line)
  puts "REVIEW #{file}\n         - #{old_line[1..].strip}\n         + #{new_line[1..].strip}"
end

fail_count = 0
review_count = 0
new_files = []
deleted_files = []
support_files = []
file = nil
removed = []
added = []

flush = lambda do
  next if removed.empty? && added.empty?

  if file.is_a?(String) && file.match?(SUPPORT_PATH)
    support_files << file
    removed = []
    added = []
    next
  end

  if removed.length != added.length
    puts "FAIL   #{file}: #{removed.length} line(s) removed, #{added.length} added (a rename is line for line)"
    removed.each { |l| puts "         #{l}" }
    added.each { |l| puts "         #{l}" }
    fail_count += 1
  else
    removed.zip(added).each_with_index do |(old_line, new_line), index|
      # A call split over several lines passes when its continuation lines are
      # unchanged apart from indentation. The shortcut applies only to lines
      # that follow an unbalanced `(` on the removed side.
      inside_call = removed[0...index].sum { |l| l.count('(') - l.count(')') }.positive?
      next if inside_call && !old_line.match?(OLD_CALL) && !new_line.match?(NEW_CALL) &&
              old_line[1..].strip == new_line[1..].strip

      # An opener pair (`create(`/`build(` at the end of the line) is clean
      # when the added line ends in the mapped verb.
      next if opener_rename?(old_line, new_line)

      # The target alone on its line is clean when it follows the camelize
      # rule (`:post,` -> `Post,`); any other target-only change reports.
      if old_line.match?(TARGET_ONLY_OLD) || new_line.match?(TARGET_ONLY_NEW)
        old_t = old_line.match(TARGET_ONLY_OLD)
        new_t = new_line.match(TARGET_ONLY_NEW)
        next if old_t && new_t && targets_match?(old_t[1], new_t[1])

        review(file, old_line, new_line)
        review_count += 1
        next
      end

      unless old_line.match?(OLD_CALL)
        puts "FAIL   #{file}: removed line is not a factory call: #{old_line.strip}"
        fail_count += 1
        next
      end

      # build_stubbed has no FactoryBakery equivalent (a documented blocker).
      if old_line.match?(/build_stubbed\(/)
        puts "FAIL   #{file}: build_stubbed has no FactoryBakery equivalent (blocker): #{old_line.strip}"
        fail_count += 1
        next
      end

      # attributes_for maps to bakery_attributes_for. The bare factory_bot
      # name on the added line is not the helper: report it.
      if old_line.match?(/\b(?:FactoryBot\.)?attributes_for\(/) &&
         new_line.match?(/\battributes_for\(/) && !new_line.match?(/\bbakery_attributes_for\(/)
        review(file, old_line, new_line)
        review_count += 1
        next
      end

      unless new_line.match?(NEW_CALL)
        puts "FAIL   #{file}: added line is not a FactoryBakery call: #{new_line.strip}"
        fail_count += 1
        next
      end

      # Every call on the line must map: same verbs and matching targets, in
      # order. A symbol compares by exact spelling or by its camelized class;
      # namespaces compare exactly.
      old_verb_targets = old_calls(old_line)
      new_verb_targets = new_calls(new_line)
      if !old_verb_targets.empty? && !new_verb_targets.empty? &&
         (old_verb_targets.length != new_verb_targets.length ||
          old_verb_targets.zip(new_verb_targets).any? do |(old_verb, old_target), (new_verb, new_target)|
            old_verb != new_verb || !targets_match?(old_target, new_target)
          end)
        review(file, old_line, new_line)
        review_count += 1
        next
      end

      # A changed literal in the arguments is never clean (residue ignores
      # whitespace).
      old_lits = literals(old_line)
      new_lits = literals(new_line)
      if !old_lits.empty? && !new_lits.empty? && old_lits != new_lits
        review(file, old_line, new_line)
        review_count += 1
        next
      end

      # A scalar call that becomes a counted Array.new changes the row count.
      if !old_line.match?(/_(?:list|pair)\b/) && new_line.match?(/Array\.new\(\s*\d+\s*\)/)
        review(file, old_line, new_line)
        review_count += 1
        next
      end

      next if residue(old_line) == residue(new_line)

      # create_list / build_list / *_pair become Array.new(n) { ... }. LIST
      # only when the count matches (a pair means 2) and the arguments and
      # traits are unchanged; anything else is a REVIEW.
      if old_line.match?(/_(?:list|pair)\b/) && new_line.match?(/Array\.new\(\d+\)/)
        count_old = old_line.match?(/_pair\b/) ? '2' : old_line[/_(?:list|pair)\(\s*:\w+\s*,\s*(\d+)/, 1]
        count_new = new_line[/Array\.new\(\s*(\d+)\s*\)/, 1]
        if count_old && count_new && count_old == count_new &&
           residue_without_count(old_line) == residue_without_count(new_line)
          puts "LIST   #{file}: #{old_line[1..].strip}  =>  #{new_line[1..].strip}"
          next
        end
      end

      review(file, old_line, new_line)
      review_count += 1
    end
  end
  removed = []
  added = []
end

$stdin.each_line(chomp: true) do |line|
  case line
  when /\Adiff --git /
    flush.call
    file = nil
  when %r{\A--- (?:a/(.+)|/dev/null)\z}
    flush.call
    deleted_marker = Regexp.last_match(1).nil?
    file = Regexp.last_match(1)
    new_files << :pending if deleted_marker
  when %r{\A\+\+\+ (?:b/(.+)|/dev/null)\z}
    path = Regexp.last_match(1)
    if file.nil? && path
      new_files.pop if new_files.last == :pending
      if path.match?(SUPPORT_PATH)
        support_files << path
      else
        new_files << path
      end
      file = :new
    elsif path.nil? && file
      if file.is_a?(String) && file.match?(SUPPORT_PATH)
        support_files << file
      else
        deleted_files << file
      end
      file = :deleted
    else
      new_files.delete(:pending)
      file = path || file
    end
  when /\A@@/
    flush.call
  when /\A-/
    removed << line unless %i[new deleted].include?(file)
  when /\A\+/
    added << line unless %i[new deleted].include?(file)
  end
end
flush.call

new_files.reject! { |f| f == :pending }
support_files.uniq.each { |f| puts "SUPPORT FILE #{f}" }
puts "NEW FILE     #{new_files.join(', ')}" unless new_files.empty?
puts "DELETED FILE #{deleted_files.join(', ')}" unless deleted_files.empty?
puts "\nsummary: #{fail_count} fail, #{review_count} review"
exit(fail_count.zero? ? 0 : 1)
