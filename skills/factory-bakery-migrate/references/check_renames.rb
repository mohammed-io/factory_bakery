#!/usr/bin/env ruby
# frozen_string_literal: true

# Checks that every changed line in the test files is a factory-call rename.
#
# Usage (from the migration worktree):
#   git diff -U0 --no-color <base>...HEAD -- spec test | ruby check_renames.rb
#
# Read-only. It reads a unified diff from stdin and prints a report.
#
# FAIL  (exit 1): a changed line that is not a factory call, or a hunk whose
#                 removed and added line counts differ.
# REVIEW (exit 0): a removed/added pair whose text differs by more than the
#                 call itself. A human or the agent must look at each one.
# NEW / DELETED FILE: listed, never judged here (helpers, definitions, and the
#                 final deletion commit are checked by hand).

OLD_CALL = /\b(?:FactoryBot\.)?(?:create|build|build_stubbed|create_list|build_list|create_pair|build_pair|
                                  build_stubbed_list|attributes_for|Fabricate|Fabricate\.build|Fabricate\.times|
                                  Fabricate\.attributes_for)\b|\.make!?\b|\.plan\b/x
NEW_CALL = /FactoryBakery\.bake!?\(|\bbake!?\(|\battributes_for\(|Array\.new\(\d+\)\s*\{/

# Reduces a line to what must stay identical across a rename.
def residue(line)
  line.sub(/\A[-+]/, '')
      .gsub(/Array\.new\(\d+\)\s*\{\s*/, '')
      .gsub(/\s*\}\s*(?=\)|\z)/, '')
      .gsub(/\b(?:FactoryBot\.)?(?:create_list|build_list|create_pair|build_pair|create|build|build_stubbed|attributes_for)\(\s*:\w+/, 'CALL(')
      .gsub(/\b(?:FactoryBakery\.)?bake!?\(\s*[A-Z][\w:]*/, 'CALL(')
      .gsub(/\battributes_for\(\s*[A-Z][\w:]*/, 'CALL(')
      .gsub(/CALL\(\s*(?:\d+,\s*)?/, 'CALL(')
      .gsub(/\s+/, '')
end

fail_count = 0
review_count = 0
new_files = []
deleted_files = []
file = nil
removed = []
added = []

flush = lambda do
  next if removed.empty? && added.empty?

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
      next if residue(old_line) == residue(new_line)

      # create_list / build_list / *_pair become Array.new(n) { ... }. The shape
      # change is expected, so it is listed for a quick look, not as a problem.
      if old_line.match?(/_(?:list|pair)\b/) && new_line.match?(/Array\.new\(\d+\)/)
        puts "LIST   #{file}: #{old_line[1..].strip}  =>  #{new_line[1..].strip}"
        next
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
      new_files << path
      file = :new
    elsif path.nil? && file
      deleted_files << file
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
puts "NEW FILE     #{new_files.join(', ')}" unless new_files.empty?
puts "DELETED FILE #{deleted_files.join(', ')}" unless deleted_files.empty?
puts "\nsummary: #{fail_count} fail, #{review_count} review"
exit(fail_count.zero? ? 0 : 1)
