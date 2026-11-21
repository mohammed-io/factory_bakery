# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    # Name-derived plausible strings, shared by the scalar StringFiller and the
    # string elements of ArrayFiller. Keeping one copy makes array elements use
    # exactly the same value logic as a plain string column.
    module PlausibleStrings
      # Identifier-like names are matched before the generic /name/ rule: a
      # person name with a space is rejected by username validators.
      IDENTIFIER_PATTERN = /user_?name|login|handle|nick_?name|screen_?name/

      # Snake-case word boundaries: a rule must not match inside another word
      # (`ip` in `description`, `name` in `hostname`) but must still match
      # `*_suffix` spellings. Each semantic rule below uses them so the table
      # stays ordered most-specific-first without one rule shadowing another.
      IP_PATTERN = /(?:^|_)ip(?:_address)?(?:_|\z)/
      HOST_PATTERN = /(?:^|_)(?:host|hostname|domain)(?:_|\z)/
      FILENAME_PATTERN = /(?:^|_)file_?name(?:_|\z)/
      TIMEZONE_PATTERN = /(?:^|_)time_?zone(?:_|\z)/
      URL_PATTERN = /(?:^|_)(?:url|uri|website|link|endpoint)(?:_|\z)/
      TITLE_PATTERN = /(?:^|_)(?:title|subject|headline)(?:_|\z)/
      # Metadata columns that merely mention a body word (content_type,
      # message_id, text_size, ...) are not prose.
      BODY_PATTERN = /(?:^|_)(?:body|raw|content|description|message|text)
                      (?!_(?:type|id|ids|count|at|on|key|hash|digest|sha|url|uri|format|size|length|level))
                      (?:_|\z)/x

      # Fixed pools of real-ish words: sampling without replacement guarantees
      # the distinct words that "clear title"/TextSentinel validators want,
      # without depending on a generator that may repeat itself.
      TITLE_WORDS = %w[consectetur adipiscing elit sed eiusmod tempor incididunt labore dolore].freeze
      LOREM_WORDS = %w[lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor].freeze
      TIMEZONES = %w[UTC Europe/London America/New_York Asia/Tokyo].freeze

      # RFC 2606 domains only. Nothing generated here points at a real host.
      RESERVED_URL_HOSTS = %w[example.com www.example.com example.test sub.example].freeze

      # Normalized column types arrive from the mapper as plain symbols. A
      # text-castable type gets its value from the same name-derived table; the
      # type rule is checked first because it is more specific than the name.
      TYPE_RULES = {
        inet: [nil, -> { generate_ip }, nil],
        cidr: [nil, -> { '192.0.2.0/24' }, nil],
        tsvector: [nil, -> { Randomness.sample(LOREM_WORDS, Randomness.rand(4..8)).join(' ') }, nil]
      }.freeze

      # Name- and title-like values are what apps derive slugs and normalized
      # keys from, and that derivation is invisible to validator-based
      # uniqueness. A six-digit random suffix gives ~1000 bakes of one model
      # distinct derived values ("Voluptas 482193" / "voluptas-482193") while
      # keeping the value readable. It draws from the bake's seeded generator,
      # so a seeded run repeats the same suffixes.
      ENTROPY_SUFFIX = 100_000..999_999

      # Ordered from most specific to least specific: the generic /name/ rule
      # would otherwise swallow "username" (a person name with a space) and
      # "hostname"/"file_name"; /address/ would swallow "ip_address". Each rule
      # is [attribute pattern, value builder, entropy separator]; a nil
      # separator means the value is not derived into a slug or key. Titles do
      # get the #58 entropy suffix, appended after the sentence.
      PATTERN_RULES = [
        [/email/, -> { FFaker::Internet.email }, nil],
        [IDENTIFIER_PATTERN, -> { generate_identifier }, nil],
        [IP_PATTERN, -> { generate_ip }, nil],
        [HOST_PATTERN, -> { generate_host }, nil],
        [FILENAME_PATTERN, -> { generate_filename }, nil],
        [TIMEZONE_PATTERN, -> { Randomness.sample(TIMEZONES) }, nil],
        [/phone/, -> { FFaker::PhoneNumber.phone_number }, nil],
        [/address|street|city/, -> { FFaker::Address.street_address }, nil],
        [URL_PATTERN, -> { generate_url }, nil],
        [TITLE_PATTERN, -> { generate_title }, ' '],
        [BODY_PATTERN, -> { generate_paragraph }, nil],
        [/priority/, -> { Randomness.rand(1..5).to_s }, nil],
        [/name/, -> { FFaker::Name.name }, ' '],
        [/slug|key/, -> { FFaker::Lorem.word }, '-'],
        [/label/, -> { FFaker::Lorem.word }, ' ']
      ].freeze

      # An attribute matching no rule gets a plain word, as before.
      DEFAULT_PATTERN_RULE = [nil, -> { FFaker::Lorem.word }, nil].freeze

      private_constant :TYPE_RULES, :PATTERN_RULES, :DEFAULT_PATTERN_RULE,
                       :IP_PATTERN, :HOST_PATTERN, :FILENAME_PATTERN, :TIMEZONE_PATTERN,
                       :URL_PATTERN, :TITLE_PATTERN, :BODY_PATTERN, :TITLE_WORDS,
                       :LOREM_WORDS, :TIMEZONES, :RESERVED_URL_HOSTS

      private

      # max_length is the cap the scalar StringFiller will truncate to, passed
      # in so the entropy suffix can be built to fit instead of being cut off
      # by that later truncation. `type` is the mapper's normalized column type.
      def generate_by_pattern(max_length: nil, type: nil)
        rule = TYPE_RULES[type] ||
               PATTERN_RULES.find { |candidate| candidate[0].match?(@attr_name) } ||
               DEFAULT_PATTERN_RULE
        value = instance_exec(&rule[1])
        rule[2] ? with_entropy(value, max_length, separator: rule[2]) : value
      end

      # A few plausible URLs for a URL-named attribute, offered to a declared
      # format before RegexGeneration. They live here, not in the generator,
      # so the caller's verifier still checks every candidate against all the
      # declared constraints (format, length, exclusion).
      def plausible_url_candidates
        return [] unless URL_PATTERN.match?(@attr_name)

        named = @attr_name.sub(URL_PATTERN, '').tr('_', '-')
        # A fresh path segment per call keeps uniqueness regeneration working:
        # a deterministic candidate would collide with a URL already baked.
        path = [named, FFaker::Lorem.word].reject(&:empty?).join('-')
        RESERVED_URL_HOSTS.map { |host| "https://#{host}/#{path}" }
      end

      def generate_ip
        "192.0.2.#{Randomness.rand(1..254)}"
      end

      def generate_host
        "#{FFaker::Lorem.word}.example.com"
      end

      def generate_filename
        "#{FFaker::Lorem.word}.png"
      end

      def generate_url
        "https://#{Randomness.sample(RESERVED_URL_HOSTS)}/#{FFaker::Lorem.word}"
      end

      # 4-8 distinct real-ish words (>= 20 chars), so a "min 15 chars, at
      # least 3 distinct words" check passes before the entropy suffix is
      # appended. Sampling without replacement is what guarantees distinctness.
      def generate_title
        Randomness.sample(TITLE_WORDS, Randomness.rand(4..8)).join(' ').capitalize
      end

      # Several sentences of real-ish words: comfortably over the 60-char
      # minimum for body-like attributes.
      def generate_paragraph
        Array.new(Randomness.rand(3..4)) do
          "#{Randomness.sample(LOREM_WORDS, Randomness.rand(6..9)).join(' ').capitalize}."
        end.join(' ')
      end

      # Append the entropy suffix, truncating the base first when a length cap
      # leaves no room for both: the suffix is the part that keeps derived
      # values distinct, so it is never the part that gets cut.
      def with_entropy(base, max_length, separator: ' ')
        suffix = entropy_suffix
        full = "#{base}#{separator}#{suffix}"
        return full if max_length.nil? || full.length <= max_length

        base_room = max_length - separator.length - suffix.length
        return "#{base[0, base_room].rstrip}#{separator}#{suffix}" if base_room >= 1

        suffix[-max_length, max_length].to_s
      end

      def entropy_suffix
        Randomness.rand(ENTROPY_SUFFIX).to_s
      end

      # Derive a plausible handle from a name but guarantee /\A[a-z][a-z0-9_]{2,19}\z/
      # regardless of what FFaker emits (no spaces, no uppercase, 3..20 chars).
      def generate_identifier
        name = "#{FFaker::Name.first_name}_#{FFaker::Name.last_name}".downcase
        slug = name.gsub(/[^a-z0-9_]+/, '_').sub(/\A[^a-z]+/, '')
        slug = 'user' if slug.empty?

        "#{slug}#{Randomness.rand(10..99)}"[0, 20]
      end
    end
  end
end
