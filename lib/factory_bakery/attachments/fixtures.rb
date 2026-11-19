# frozen_string_literal: true

module FactoryBakery
  module Attachments
    # The bundled fixtures in preference order. The first fixture an
    # attachment's allowed content types accept is the one used, so an
    # unrestricted attachment gets the 1x1 PNG.
    module Fixtures
      module_function

      def all
        @all ||= [
          Fixture.new('image/png', 'png.png'),
          Fixture.new('image/jpeg', 'jpeg.jpg'),
          Fixture.new('image/gif', 'gif.gif'),
          Fixture.new('image/webp', 'webp.webp'),
          Fixture.new('video/mp4', 'video.mp4'),
          Fixture.new('audio/mpeg', 'audio.mp3'),
          Fixture.new('application/pdf', 'document.pdf'),
          Fixture.new('text/plain', 'text.txt')
        ].freeze
      end

      def default
        all.first
      end

      # The first fixture whose content type satisfies one of the allowed
      # rules, or the default when the attachment declares no restriction.
      # A rule is a content type string (with an optional `type/*` wildcard)
      # or a Regexp, which is how attachment validators express them; a rule
      # in any other form is ignored and falls back to the default.
      def for(allowed)
        rules = usable_rules(allowed)
        return default if rules.empty?

        match(all, rules) ||
          raise(Error, "no bundled attachment fixture matches #{rules.inspect}; " \
                       'declare the attachment explicitly or allow one of ' \
                       "#{all.map(&:content_type).join(', ')}")
      end

      def usable_rules(allowed)
        Array(allowed).select do |rule|
          (rule.is_a?(String) && !rule.empty?) || rule.is_a?(Regexp)
        end
      end

      def match(fixtures, allowed)
        fixtures.find { |fixture| allowed.any? { |rule| matches?(rule, fixture.content_type) } }
      end

      def matches?(rule, content_type)
        return rule.match?(content_type) if rule.is_a?(Regexp)

        pattern = rule.to_s
        return true if pattern == content_type
        return content_type.start_with?(pattern.delete_suffix('*')) if pattern.end_with?('/*')

        false
      end
    end
  end
end
