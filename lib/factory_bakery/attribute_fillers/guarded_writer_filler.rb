# frozen_string_literal: true

module FactoryBakery
  module AttributeFillers
    # The blank value for an attribute whose writer has side effects.
    #
    # Mastodon's Remotable defines `avatar_remote_url=` (and its siblings),
    # which downloads the URL it is handed. A heuristic value would perform
    # network I/O inside a bake and usually fail, so such an attribute is never
    # handed one -- not even on the fill-optional path. The mapper marks it with
    # the normalized `guarded_writer` fact, so this filler names no framework
    # and no model (ADR-0001).
    #
    # The routing policy leaves a nullable or defaulted attribute untouched
    # (no setter call at all, so a column default survives) and routes only a
    # NOT NULL column without a default here: the database still needs a value,
    # and an empty String is the one that reaches the writer as no URL at all.
    class GuardedWriterFiller
      def initialize(model_class, attr_name); end

      def call(_context = nil)
        ''
      end
    end
  end
end
