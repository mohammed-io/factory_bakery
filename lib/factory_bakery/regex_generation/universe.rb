# frozen_string_literal: true

module FactoryBakery
  module RegexGeneration
    # The characters a character-matching node (set, type, property, dot) is
    # sampled from. Candidates are tried in tiers: alphanumerics first (the
    # most natural fake data), then the rest of printable ASCII, and only when
    # neither matches anything (`[\r\n]`, `\p{Greek}`, `[а-я]`) a wide pool of
    # control characters, curated Unicode samples and a stride across the
    # codepoint space. Membership is always decided by Onigmo itself (see
    # CharPools), so the sample can never contain a character the node rejects.
    class Universe
      ALNUM = [*'0'..'9', *'A'..'Z', *'a'..'z'].freeze
      PUNCT = ((32..126).map(&:chr) - ALNUM).freeze

      SURROGATES = (0xD800..0xDFFF)
      CONTROLS = [*0..31, 127].freeze
      # A few characters from the scripts, symbols and digits regexes name.
      CURATED = %w[é ñ ü ß ø Ω α β я ж א ب क ก あ ア 中 文 한 😀 € £ © ° ½ ² ٣ ०].map(&:ord).freeze
      # One sample every 41 codepoints through the BMP and the first two
      # supplementary planes reaches every sizeable block (Han, Hangul, ...).
      STRIDE = (0x80..0x2FFFF).step(41).to_a.freeze

      attr_reader :encoding, :wide

      def initialize(encoding, max_codepoint, wide_points)
        @encoding = encoding
        @max_codepoint = max_codepoint
        @wide = wide_points.select { |point| representable?(point) }.map { |point| char(point) }.freeze
      end

      def char(codepoint)
        codepoint.chr(@encoding)
      end

      def representable?(codepoint)
        codepoint <= @max_codepoint && !SURROGATES.cover?(codepoint)
      end

      UTF8 = new(Encoding::UTF_8, 0x10FFFF, CONTROLS + CURATED + STRIDE)
      BINARY = new(Encoding::BINARY, 255, CONTROLS + (128..255).to_a)

      def self.for(encoding)
        encoding == Encoding::BINARY ? BINARY : UTF8
      end
    end
  end
end
