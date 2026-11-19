# frozen_string_literal: true

module FactoryBakery
  module RegexGeneration
    # Classifies a regexp_parser node into the kind the generator knows how to
    # render. A kind names a `render_<kind>` method in the generator and a
    # `measure_<kind>` method in the Plan. A node type that is not listed
    # raises KeyError, which `generate` turns into "no candidate".
    module NodeKind
      BY_TYPE_AND_TOKEN = {
        %i[group comment] => :skip,
        %i[group absence] => :absence,
        %i[group capture] => :capture,
        %i[group named] => :capture,
        %i[meta dot] => :pool,
        %i[meta alternation] => :alternation,
        %i[type linebreak] => :linebreak,
        %i[type xgrapheme] => :grapheme,
        %i[backref name_call] => :call,
        %i[backref number_call] => :call,
        %i[backref number_rel_call] => :call,
        %i[assertion lookahead] => :lookahead,
        %i[assertion lookbehind] => :lookbehind,
        %i[assertion nlookahead] => :skip,
        %i[assertion nlookbehind] => :skip,
        %i[anchor word_boundary] => :word_boundary,
        %i[anchor nonword_boundary] => :nonword_boundary
      }.freeze

      BY_TYPE = {
        literal: :literal,
        escape: :escape,
        set: :pool,
        type: :pool,
        property: :pool,
        nonproperty: :pool,
        anchor: :skip,
        keep: :skip,
        free_space: :skip,
        group: :sequence,
        expression: :sequence,
        backref: :backref,
        conditional: :conditional
      }.freeze

      def self.of(node)
        BY_TYPE_AND_TOKEN.fetch([node.type, node.token]) { BY_TYPE.fetch(node.type) }
      end
    end
  end
end
