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
#                 attributes_for -> bake/bake!), a changed bake target, a
#                 changed list count, a changed list argument, or a pair whose
#                 text differs by more than the call. A human or the agent must
#                 look at each one.
# LIST (exit 0): a create_list/build_list/*_pair rename to Array.new(n) whose
#                 count and arguments are unchanged.
# SUPPORT FILE: a helper, definition or suite-wiring file (spec|test bakery or
#                 support directories, spec/rails_helper.rb, spec/spec_helper.rb,
#                 test/test_helper.rb). Listed, never judged.
# NEW / DELETED FILE: listed, never judged here (the final deletion commit is
#                 checked by hand).

OLD_CALL = /\b(?:FactoryBot\.)?(?:create|build|build_stubbed|create_list|build_list|create_pair|build_pair|
                                  build_stubbed_list|attributes_for|Fabricate|Fabricate\.build|Fabricate\.times|
                                  Fabricate\.attributes_for)\b|\.make!?\b|\.plan\b/x
NEW_CALL = /FactoryBakery\.bake!?\(|\bbake!?\(|\b(?:bakery_)?attributes_for\(|Array\.new\(\d+\)\s*\{/

# Every factory call on a line, with its target. Removed lines scan OLD_CALLS,
# added lines NEW_CALLS; the two lists of [verb, target] pairs must be equal.
OLD_CALLS = /\b(?:FactoryBot\.)?(create|build|attributes_for)(?:_list|_pair)?\(\s*:(\w+)/
NEW_CALLS = /\b(?:FactoryBakery\.)?(bake!?|bakery_attributes_for)\(\s*([A-Z][\w:]*|:\w+)/

# The FactoryBakery verb each removed factory_bot verb must map to.
OLD_VERBS = { 'create' => 'bake!', 'build' => 'bake', 'attributes_for' => 'bakery_attributes_for' }.freeze

# The factory_bot calls residue() normalizes away.
OLD_RESIDUE = /\b(?:FactoryBot\.)?(?:create_list|build_list|create_pair|build_pair|
                               create|build|build_stubbed|attributes_for)\(\s*:\w+/x

# A helper or definition file, and the test-suite wiring files. Changes there
# are printed and never judged.
SUPPORT_PATH = %r{\A(?:(?:spec|test)/(?:bakery|support)/|spec/rails_helper\.rb\z|
                        spec/spec_helper\.rb\z|test/test_helper\.rb\z)}x

# Camelize a factory_bot target so :admin_post compares equal to AdminPost.
# Each segment keeps its case after the first letter is upcased (w[0].upcase +
# w[1..], not capitalize, so inner capitals survive).
def camelize_target(token)
  token.delete_prefix(':').split('::').map do |part|
    part.split('_').map { |word| word[0].upcase + word[1..].to_s }.join
  end.join('::')
end

# Namespaces do not distinguish a target: :admin_post, AdminPost and
# Admin::Post are one target.
def flatten_target(target)
  target.delete('::')
end

# All factory calls on a removed line, as an ordered list of [verb, target]
# pairs. The verb is mapped to its FactoryBakery spelling and the target is
# camelized, so the list compares against the added line's.
def old_calls(line)
  line.scan(OLD_CALLS).map do |verb, target|
    [OLD_VERBS.fetch(verb), flatten_target(camelize_target(":#{target}"))]
  end
end

# All factory calls on an added line, as an ordered list of [verb, target]
# pairs. Array.new(n) { wrappers are ignored here (the LIST branch checks the
# count); the verb stays as written and the target case stays as written, a
# symbol camelized, namespaces flattened.
def new_calls(line)
  body = line.sub(/\A\+/, '').gsub(/Array\.new\(\d+\)\s*\{\s*/, '')
  body.scan(NEW_CALLS).map do |verb, target|
    normalized = target.start_with?(':') ? camelize_target(target) : target
    [verb, flatten_target(normalized)]
  end
end

# Quoted literals must carry over unchanged. residue ignores whitespace, so a
# changed literal word is caught here.
def literals(line)
  line.scan(/'[^']*'|"[^"]*"/)
end

# Reduces a line to what must stay identical across a rename. The list count
# is kept, so a changed count is visible; the LIST branch strips it again.
def residue(line)
  line.sub(/\A[-+]/, '')
      .gsub(/Array\.new\(\d+\)\s*\{\s*/, '')
      .gsub(/(\s*\})+\s*(?=\)|\z)/, '')
      .gsub(OLD_RESIDUE, 'CALL(')
      .gsub(/\b(?:FactoryBakery\.)?bake!?\(\s*(?:[A-Z][\w:]*|:\w+)/, 'CALL(')
      .gsub(/\b(?:bakery_)?attributes_for\(\s*(?:[A-Z][\w:]*|:\w+)/, 'CALL(')
      .gsub(/CALL\(\s*/, 'CALL(')
      .gsub(/\s+/, '')
end

# residue with the list count stripped, so a list rename compares by its
# arguments and traits alone.
def residue_without_count(line)
  residue(line).sub(/CALL\(,\d+(?=[,)])/, 'CALL(')
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
    removed.zip(added).each do |old_line, new_line|
      # A call split over several lines passes when its continuation lines are
      # unchanged apart from indentation.
      next if !old_line.match?(OLD_CALL) && !new_line.match?(NEW_CALL) &&
              old_line[1..].strip == new_line[1..].strip

      unless old_line.match?(OLD_CALL)
        puts "FAIL   #{file}: removed line is not a factory call: #{old_line.strip}"
        fail_count += 1
        next
      end

      # build_stubbed has no FactoryBakery equivalent (a documented blocker).
      if old_line.match?(/build_stubbed/)
        puts "FAIL   #{file}: build_stubbed has no FactoryBakery equivalent (blocker): #{old_line.strip}"
        fail_count += 1
        next
      end

      unless new_line.match?(NEW_CALL)
        puts "FAIL   #{file}: added line is not a FactoryBakery call: #{new_line.strip}"
        fail_count += 1
        next
      end

      # Every call on the line must map: same verbs and same targets, in order.
      old_verb_targets = old_calls(old_line)
      new_verb_targets = new_calls(new_line)
      if !old_verb_targets.empty? && !new_verb_targets.empty? && old_verb_targets != new_verb_targets
        puts "REVIEW #{file}\n         - #{old_line[1..].strip}\n         + #{new_line[1..].strip}"
        review_count += 1
        next
      end

      # A changed literal in the arguments is never clean (residue ignores
      # whitespace).
      old_lits = literals(old_line)
      new_lits = literals(new_line)
      if !old_lits.empty? && !new_lits.empty? && old_lits != new_lits
        puts "REVIEW #{file}\n         - #{old_line[1..].strip}\n         + #{new_line[1..].strip}"
        review_count += 1
        next
      end

      next if residue(old_line) == residue(new_line)

      # create_list / build_list / *_pair become Array.new(n) { ... }. LIST
      # only when the count matches and the arguments and traits are
      # unchanged; anything else is a REVIEW.
      if old_line.match?(/_(?:list|pair)\b/) && new_line.match?(/Array\.new\(\d+\)/)
        count_old = old_line.match?(/_pair\b/) ? '2' : old_line[/_(?:list|pair)\(\s*:\w+\s*,\s*(\d+)/, 1]
        count_new = new_line[/Array\.new\(\s*(\d+)\s*\)/, 1]
        if count_old && count_new && count_old == count_new &&
           residue_without_count(old_line) == residue_without_count(new_line)
          puts "LIST   #{file}: #{old_line[1..].strip}  =>  #{new_line[1..].strip}"
          next
        end
      end

      puts "REVIEW #{file}\n         - #{old_line[1..].strip}\n         + #{new_line[1..].strip}"
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
