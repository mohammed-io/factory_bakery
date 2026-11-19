# frozen_string_literal: true

require 'spec_helper'
require 'uri'
require_relative '../../support/regex_generation_matchers'

# Real-world regexes (the shapes Rails apps, Mastodon and Discourse validate
# with). Every one must generate a matching value at least 95% of the time over
# 200 seeded generations; a failure names the regex and a bad sample.
RSpec.describe 'RegexGeneration corpus' do
  corpus = {
    # Emails
    'URI::MailTo::EMAIL_REGEXP' => URI::MailTo::EMAIL_REGEXP,
    'email: not-@-or-space (Devise default)' => /\A[^@\s]+@[^@\s]+\z/,
    'email: Rails guides' => /\A[\w+.-]+@[a-z\d-]+(\.[a-z\d-]+)*\.[a-z]+\z/i,
    # URLs
    'URL: URI make_regexp for http/https (Discourse WebHook lookahead)' =>
      URI::DEFAULT_PARSER.make_regexp(%w[http https]),
    'URL: WebHook lookahead then scheme' => %r{\A(?=(?i:http|https):)[a-z]+://[^\s/]+(?:/\S*)?\z}i,
    'URL: simple http(s)' => %r{\Ahttps?://[\w.-]+(?::\d+)?(?:/[\w/.%-]*)?(?:\?[\w=&%.-]*)?\z},
    'URL: domain name' => /\A(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}\z/i,
    'URL: hostname' => /\A[a-z0-9.-]+\z/i,
    # Identifiers
    'UUID' => /\A\h{8}-\h{4}-\h{4}-\h{4}-\h{12}\z/,
    'UUID v4' => /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i,
    'ULID' => /\A[0-7][0-9A-HJKMNP-TV-Z]{25}\z/,
    'Mongo ObjectId' => /\A[0-9a-f]{24}\z/,
    'MD5 digest' => /\A\h{32}\z/,
    'SHA-256 digest' => /\A\h{64}\z/,
    'hex string' => /\A\h+\z/,
    'semver' => /\A(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?
                  (?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?\z/x,
    'version number' => /\Av?\d+(\.\d+){1,2}\z/,
    'JWT shape' => /\A[\w-]+\.[\w-]+\.[\w-]+\z/,
    'base64' => %r{\A(?:[A-Za-z0-9+/]{4})*(?:[A-Za-z0-9+/]{2}==|[A-Za-z0-9+/]{3}=)?\z},
    # Network
    'IPv4' => /\A(?:(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\.){3}(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)\z/,
    'IPv6 (simplified, full form)' => /\A(?:\h{1,4}:){7}\h{1,4}\z/,
    'IPv6 (simplified, 2-8 groups)' => /\A(?:\h{1,4}:){1,7}\h{1,4}\z/,
    'MAC address' => /\A(?:\h{2}[:-]){5}\h{2}\z/,
    # Colors
    'hex color' => /\A#?(\h{3}|\h{6})\z/,
    'hex color alternation, unanchored branches' => /\A(?:\h{3}|\h{6})\z/,
    'CSS color names' => /\A(?:red|green|blue|black|white|orange|purple|yellow)\z/i,
    'rgb()' => /\Argb\(\s*\d{1,3}\s*,\s*\d{1,3}\s*,\s*\d{1,3}\s*\)\z/,
    # Names and handles
    'slug' => /\A[a-z0-9]+(?:-[a-z0-9]+)*\z/,
    'Mastodon local username' => /\A[a-z0-9_]+([a-z0-9_.-]+[a-z0-9_]+)?\z/i,
    'Mastodon username (separators)' => /\A[a-z0-9_]+([.-]+[a-z0-9_]+)*\z/i,
    'Mastodon remote username' => /\A[a-z0-9_]+([a-z0-9_.-]+[a-z0-9_]+)?(?:@[a-z0-9.-]+[a-z0-9])?\z/i,
    'Discourse ThemeField name' => /\A[a-z_][a-z0-9_-]*\z/i,
    'Mastodon Keypair' => /\A#[A-Z0-9-]+\Z/i,
    'Twitter handle' => /\A@?[A-Za-z0-9_]{1,15}\z/,
    'hashtag' => /\A#[[:alnum:]_]+\z/,
    'Unicode name' => /\A\p{L}[\p{L}\s'-]*\z/,
    'title-cased name' => /\A[A-Z][a-z]+(?: [A-Z][a-z]+)*\z/,
    'capitalized word (POSIX)' => /\A[[:upper:]][[:lower:]]+\z/,
    'negated POSIX class' => /\A[[:^alpha:]]+\z/,
    'Cyrillic word' => /\A\p{Cyrillic}+\z/,
    'emoji range' => /\A[\u{1F600}-\u{1F64F}]{1,3}\z/,
    'file name with extension' => /\A[\w\-. ]+\.(?:png|jpe?g|gif|pdf)\z/i,
    # Dates and times
    'ISO date' => /\A\d{4}-(?:0[1-9]|1[0-2])-(?:0[1-9]|[12]\d|3[01])\z/,
    'ISO time' => /\A(?:[01]\d|2[0-3]):[0-5]\d:[0-5]\d\z/,
    'ISO datetime' => /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})\z/,
    'timezone Area/City' => %r{\A[A-Z][a-z]+/[A-Z][a-z_]+\z},
    'cron expression' => /\A(?:\*|\d{1,2}(?:-\d{1,2})?)(?: (?:\*|\d{1,2}(?:-\d{1,2})?)){4}\z/,
    # Phones, postcodes, money, cards
    'phone E.164' => /\A\+[1-9]\d{1,14}\z/,
    'phone US' => /\A\(\d{3}\) \d{3}-\d{4}\z/,
    'phone loose' => /\A\+?\d[\d\s().-]{6,}\d\z/,
    'US ZIP' => /\A\d{5}(?:-\d{4})?\z/,
    'UK postcode' => /\A[A-Z]{1,2}\d[A-Z\d]? ?\d[A-Z]{2}\z/i,
    'Canadian postal code' => /\A[ABCEGHJ-NPRSTVXY]\d[ABCEGHJ-NPRSTV-Z] ?\d[ABCEGHJ-NPRSTV-Z]\d\z/i,
    'Dutch postcode' => /\A[1-9]\d{3} ?[A-Z]{2}\z/i,
    'credit card digit groups' => /\A\d{4}(?: \d{4}){3}\z/,
    'credit card with consistent separator (backreference)' => /\A\d{4}([ -]?)\d{4}\1\d{4}\1\d{4}\z/,
    'IBAN shape' => /\A[A-Z]{2}\d{2}[A-Z0-9]{11,30}\z/,
    'ISBN-13' => /\A97[89]-?\d{10}\z/,
    'US SSN' => /\A\d{3}-\d{2}-\d{4}\z/,
    'currency' => /\A\$\d{1,3}(?:,\d{3})*(?:\.\d{2})?\z/,
    'percentage' => /\A\d{1,3}(?:\.\d+)?%\z/,
    # Advanced constructs
    'backreference' => /\A(\w)\1\z/,
    'named backreference' => /\A(?<quote>["'])\w+\k<quote>\z/,
    'conditional' => /\A(\()?\d+(?(1)\))\z/,
    'free-spacing with comments' => /
      \A
      (?<year>\d{4})   # four digits
      -
      (?<month>\d{2})  # two digits
      -
      (?<day>\d{2})    # two digits
      \z
    /x,
    'absence operator (C comment)' => %r{\A/\*(?~\*/)\*/\z},
    'lookbehind' => /(?<=\$)\d+(?:\.\d{2})?/,
    'negative lookahead' => /\A(?!.*\s)\S{8,32}\z/,
    'password policy lookaheads' => /\A(?=.*\d)(?=.*[a-z])(?=.*[A-Z]).{8,}\z/,
    'intersection set' => /\A[a-z&&[^aeiou]]{3,8}\z/,
    'word-bounded token' => /\b[A-Z]{3}\b/,
    'linebreak between words' => /\A\w+\R\w+\z/,
    'recursive balanced parentheses' => /\A(?<paren>\((?:[a-z]|\g<paren>)*\))\z/
  }.freeze

  it 'covers at least 60 regexes' do
    expect(corpus.size).to be >= 60
  end

  corpus.each do |name, regexp|
    it "generates matching values for #{name}" do
      expect(regexp).to generate_matching(count: 200, min_rate: 0.95)
    end
  end
end
