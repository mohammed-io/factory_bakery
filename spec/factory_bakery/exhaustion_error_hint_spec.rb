# frozen_string_literal: true

require 'spec_helper'

# When a value cannot be generated, the error says why and shows, as code that
# can be pasted, the two ways to give the attribute a value.
RSpec.describe 'actionable generation errors' do
  def message_of(&block)
    block.call
    nil
  rescue FactoryBakery::Error => e
    e.message
  end

  describe 'a regex the generator cannot solve' do
    let!(:coupon) do
      define_model('HintCoupon', code: :string) do
        validates :code, format: { with: /\Afoo(?=bar)\z/ }
      end
    end

    it 'keeps the established first line' do
      expect(message_of { FactoryBakery.bake(coupon) })
        .to match(/could not generate a format-compliant value for HintCoupon#code/)
    end

    it 'says the regex cannot be solved and why it may be unsolvable' do
      message = message_of { FactoryBakery.bake(coupon) }

      expect(message).to include('The regex generator cannot solve /\Afoo(?=bar)\z/')
      expect(message).to match(/unsatisfiable, too large or too complex/)
    end

    it 'shows the definition and the call-site spelling with the model and attribute filled in' do
      message = message_of { FactoryBakery.bake(coupon) }

      hint = "'<a value matching /\\Afoo(?=bar)\\z/>'"
      expect(message).to include("FactoryBakery.define(HintCoupon) do\n    code { #{hint} }\n  end")
      expect(message).to include("FactoryBakery.bake(HintCoupon, code: #{hint})")
      expect(message).to include('docs/diagnostics.md#format-exhaustion')
    end

    it 'is solved by doing what the message says' do
      FactoryBakery.define(coupon) { code { 'foo' } }

      expect(FactoryBakery.bake(coupon).code).to eq('foo')
      expect(FactoryBakery.bake(coupon, code: 'foo').code).to eq('foo')
    end
  end

  describe 'numeric constraints that leave no value' do
    let!(:ticket) do
      define_model('HintTicket', seats: :integer) do
        validates :seats, numericality: { only_integer: true, other_than: 3,
                                          greater_than_or_equal_to: 3, less_than_or_equal_to: 3 }
      end
    end

    it 'shows the same override spelling with a link to its catalog entry' do
      message = message_of { FactoryBakery.bake(ticket) }

      expect(message).to include('numeric constraints for HintTicket#seats')
      expect(message).to include("FactoryBakery.define(HintTicket) do\n    seats { '<a number that satisfies the")
      expect(message).to include('docs/diagnostics.md#numeric-constraint-exhaustion')
    end
  end
end
