# frozen_string_literal: true

require 'spec_helper'

# Issue #48: a username-like attribute must get an identifier-shaped value,
# never a person name. The generic /name/ rule used to run before /username/,
# so "username" received "Florinda Conn" and failed username validators.
RSpec.describe 'identifier-shaped strings (issue #48)' do
  include DefineConstantMacros

  let(:identifier_pattern) { /\A[a-z][a-z0-9_]{2,19}\z/ }
  let(:person_name_pattern) { /\A[a-zA-Z]+\s+[a-zA-Z]/ }

  describe 'unconstrained identifier-like attributes' do
    let!(:BakedUser) do
      define_model('BakedUser', username: :string, user_name: :string, login: :string,
                                handle: :string, nickname: :string, screen_name: :string)
    end

    it 'generates identifier-shaped values for every identifier-like name' do
      record = FactoryBakery.bake(BakedUser, fill_optional: true)

      %i[username user_name login handle nickname screen_name].each do |attribute|
        expect(record.public_send(attribute)).to match(identifier_pattern)
      end
    end
  end

  describe 'ordering against the generic name rule' do
    let!(:OrderingUser) do
      define_model('OrderingUser', username: :string, nickname: :string, screen_name: :string,
                                   name: :string, first_name: :string, display_name: :string)
    end

    it 'keeps name-shaped identifiers distinct from person names' do
      record = FactoryBakery.bake(OrderingUser, fill_optional: true)

      %i[username nickname screen_name].each do |attribute|
        expect(record.public_send(attribute)).to match(identifier_pattern)
      end
      %i[name first_name display_name].each do |attribute|
        expect(record.public_send(attribute)).to match(person_name_pattern)
      end
    end
  end

  describe 'declared constraints take precedence' do
    it 'honors a declared format over the identifier heuristic' do
      model = define_model('FormattedUsername', username: :string) do
        validates :username, format: { with: /\A[0-9]{5}\z/ }
      end

      expect(FactoryBakery.bake(model).username).to match(/\A[0-9]{5}\z/)
    end

    it 'honors a declared length over the identifier heuristic' do
      model = define_model('ShortUsername', username: :string) do
        validates :username, length: { is: 2 }
      end

      expect(FactoryBakery.bake(model).username.length).to eq(2)
    end
  end

  describe 'shared logic for string array elements' do
    it 'uses the identifier heuristic for a username-like string array' do
      constraints = FactoryBakery::ConstraintSet.new(
        model_class: Object, attr_name: 'usernames', type: :array, array_element_type: :string
      )
      allow(FactoryBakery::ConstraintSet).to receive(:for).with(Object, 'usernames').and_return(constraints)
      filler = FactoryBakery::AttributeFillers::ArrayFiller.new(Object, 'usernames')

      expect(filler.call).to all(match(identifier_pattern))
    end

    it 'bakes identifier-shaped elements on PostgreSQL array columns' do
      skip 'native array columns require PostgreSQL' unless DatabaseSupport.postgresql?

      model = define_model('UsernameList', usernames: { type: :string, array: true })

      expect(FactoryBakery.bake(model).usernames).to all(match(identifier_pattern))
    end
  end
end
