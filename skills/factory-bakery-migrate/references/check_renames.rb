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
# FAIL  (exit 1): a changed line that is not a factory call, or a hunk whose
#                 removed and added line counts differ.
# REVIEW (exit 0): a removed/added pair whose text differs by more than the
#                 call itself, a changed bake target, a changed list count, or
#                 a changed list argument. A human or the agent must look at
#                 each one.
# LIST (exit 0): a create_list/build_list/*_pair rename to Array.new(n) whose
#                 count and arguments are unchanged.
# SUPPORT FILE: a helper, definition or suite-wiring file (spec|test bakery or
#                 support directories, spec/rails_helper.rb, test/test_helper.rb).
#                 Listed, never judged.
# NEW / DELETED FILE: listed, never judged here (helpers, definitions, and the
#                 final deletion commit are checked by hand).

OLD_CALL = /\b(?:FactoryBot\.)?(?:create|build|build_stubbed|create_list|build_list|create_pair|build_pair|
                                  build_stubbed_list|attributes_for|Fabricate|Fabricate\.build|Fabricate\.times|
                                  Fabricate\.attributes_for)\b|\.make!?\b|\.plan\b/x
NEW_CALL = /FactoryBakery\.bake!?\(|\bbake!?\(|\b(?:bakery_)?attributes_for\(|Array\.new\(\d+\)\s*\{/

# A helper or definition file, and the test-suite wiring files. Changes there
# are printed and never judged.
SUPPORT_PATH = %r{\A(?:(?:spec|test)/(?:bakery|support)/|spec/rails_helper\.rb\z|test/test_helper\.rb\z)}

# Reduces a line to what must stay identical across a rename. The list count
# is kept, so a changed count is visible; the LIST branch strips it again.
def residue(line)
  line.sub(/\A[-+]/, '')
      .gsub(/Array\.new\(\d+\)\s*\{\s*/, '')
      .gsub(/(\s*\})+\s*(?=\)|\z)/, '')
      .gsub(/\b(?:FactoryBot\.)?(?:create_list|build_list|create_pair|build_pair|create|build|build_stubbed|attributes_for)\(\s*:\w+/, 'CALL(')
      .gsub(/\b(?:FactoryBakery\.)?bake!?\(\s*(?:[A-Z][\w:]*|:\w+)/, 'CALL(')
      .gsub(/\b(?:bakery_)?attributes_for\(\s*(?:[A-Z][\w:]*|:\w+)/, 'CALL(')
      .gsub(/CALL\(\s*/, 'CALL(')
      .gsub(/\s+/, '')
end

# Camelize a factory target so :admin_post and AdminPost compare equal.
def camelize_target(token)
  token.sub(/\A:/, '').split('::').map { |part| part.split('_').map(&:capitalize).join }.join('::')
end

OLD_TARGET = /\b(?:FactoryBot\.)?(?:create_list|build_list|create_pair|build_pair|build_stubbed_list|
                               attributes_for|Fabricate\.attributes_for|Fabricate\.build|Fabricate|create|build|build_stubbed)\(\s*:(\w+)/x

# The factory_bot target a removed line bakes (:post), camelized for comparison.
def old_target(line)
  match = line.match(OLD_TARGET)
  match ? camelize_target(match[1]) : nil
end

# The bake target an added line names (a class or :symbol), on the line itself
# or inside the Array.new block. Nil when there is none.
def new_target(line)
  body = line.gsub(/Array\.new\(\d+\)\s*\{\s*/, '')
  match = body.match(/\b(?:FactoryBakery\.)?bake!?\(\s*([A-Z][\w:]*|:\w+)/) ||
          body.match(/\b(?:bakery_)?attributes_for\(\s*([A-Z][\w:]*|:\w+)/)
  match ? camelize_target(match[1]) : nil
end

# Quoted literals must carry over unchanged. residue ignores whitespace, so a
# changed literal word is caught here.
def literals(line)
  line.scan(/'[^']*'|"[^"]*"/)
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
      unless old_line.match?(OLD_CALL)
        puts "FAIL   #{file}: removed line is not a factory call: #{old_line.strip}"
        fail_count += 1
        next
      end
      unless new_line.match?(NEW_CALL)
        puts "FAIL   #{file}: added line is not a FactoryBakery call: #{new_line.strip}"
        fail_count += 1
        next
      end

      # A changed literal in the arguments is never clean (residue ignores
      # whitespace), and neither is a different bake target.
      old_lits = literals(old_line)
      new_lits = literals(new_line)
      old_tgt = old_target(old_line)
      new_tgt = new_target(new_line)
      if (!old_lits.empty? && !new_lits.empty? && old_lits != new_lits) ||
         (old_tgt && new_tgt && old_tgt != new_tgt)
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
