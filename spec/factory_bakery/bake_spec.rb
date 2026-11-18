# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'FactoryBakery public bake API' do
  include DefineConstantMacros

  describe '.bake' do
    it 'fills every column heuristically and returns an unsaved instance' do
      model = define_model('FilledRecord',
                           title: :string,
                           count: :integer,
                           ratio: :float,
                           amount: :decimal,
                           active: :boolean,
                           published_on: :date,
                           published_at: :datetime)

      record = FactoryBakery.bake(model)

      expect(record).to be_a(model)
      expect(record).to be_new_record
      expect(record.id).to be_nil
      expect(record.title).to be_a(String)
      expect(record.title).not_to be_empty
      expect(record.count).to be_a(Integer)
      expect(record.ratio).to be_a(Float)
      expect(record.amount).to be_a(Numeric)
      expect([true, false]).to include(record.active)
      expect(record.published_on).to be_a(Date)
      expect(record.published_at).to respond_to(:to_time)
      expect(record).to be_valid
    end

    describe 'validator-driven values' do
      it 'respects length validators' do
        model = define_model('Bounded', code: :string, bio: :string, slug: :string) do
          validates :code, length: { is: 5 }
          validates :bio, length: { minimum: 20, maximum: 30 }
          validates :slug, length: { in: 3..8 }
        end

        record = FactoryBakery.bake(model)

        expect(record.code.length).to eq(5)
        expect(record.bio.length).to be_between(20, 30).inclusive
        expect(record.slug.length).to be_between(3, 8).inclusive
        expect(record).to be_valid
      end

      it 'respects numericality bounds and ranges' do
        model = define_model('Numerics', age: :integer, score: :decimal) do
          validates :age, numericality: { greater_than: 18, less_than: 65 }
          validates :score, numericality: { in: 1..10 }
        end

        record = FactoryBakery.bake(model)

        expect(record.age).to be_between(19, 64).inclusive
        expect(record.score).to be_between(1, 10).inclusive
        expect(record).to be_valid
      end

      it 'picks a value from an inclusion list' do
        model = define_model('Task', status: :string) do
          validates :status, inclusion: { in: %w[pending in_progress completed] }
        end

        record = FactoryBakery.bake(model)

        expect(%w[pending in_progress completed]).to include(record.status)
        expect(record).to be_valid
      end

      it 'matches confirmation attributes to their source attribute' do
        model = define_model('Signup', email: :string, email_confirmation: :string) do
          validates :email, confirmation: true
        end

        record = FactoryBakery.bake(model)

        expect(record.email).not_to be_empty
        expect(record.email_confirmation).to eq(record.email)
        expect(record).to be_valid
      end

      it 'fills acceptance attributes with the accepted value' do
        model = define_model('Agreement', terms: :string) do
          validates :terms, acceptance: { accept: 'yes' }
        end

        record = FactoryBakery.bake(model)

        expect(record.terms).to eq('yes')
        expect(record).to be_valid
      end

      it 'fills enum attributes with a defined enum value' do
        model = define_model('Order', status: :integer) do
          enum :status, { pending: 0, shipped: 1, delivered: 2 }
        end

        record = FactoryBakery.bake(model)

        expect(%w[pending shipped delivered]).to include(record.status)
        expect(record).to be_valid
      end
    end

    describe 'call-site overrides' do
      it 'uses overridden values and still fills every other attribute' do
        model = define_model('Overridable', email: :string, age: :integer, city: :string) do
          validates :email, presence: true
          validates :age, numericality: { greater_than: 0 }
          validates :city, presence: true
        end

        record = FactoryBakery.bake(model, email: 'x@y.z')

        expect(record.email).to eq('x@y.z')
        expect(record.age).to be_a(Integer)
        expect(record.age).to be > 0
        expect(record.city).to be_a(String)
        expect(record.city).not_to be_empty
        expect(record).to be_valid
      end

      it 'propagates an overridden source value to its confirmation attribute' do
        model = define_model('ConfirmedSignup', email: :string, email_confirmation: :string) do
          validates :email, confirmation: true
        end

        record = FactoryBakery.bake(model, email: 'known@example.com')

        expect(record.email).to eq('known@example.com')
        expect(record.email_confirmation).to eq('known@example.com')
      end

      it 'lets an override on the confirmation attribute itself win' do
        model = define_model('ExplicitConfirmation', email: :string, email_confirmation: :string) do
          validates :email, confirmation: true
        end

        record = FactoryBakery.bake(model, email: 'source@example.com', email_confirmation: 'explicit@example.com')

        expect(record.email).to eq('source@example.com')
        expect(record.email_confirmation).to eq('explicit@example.com')
      end
    end

    describe 'attributes routed to noop by the filler selector' do
      let!(:model) do
        define_model('WithDefault',
                     state: { type: :string, default: 'draft' },
                     secret: :string)
      end

      it 'leaves columns with database defaults to the database' do
        record = FactoryBakery.bake(model)

        expect(record.state).to eq('draft')
        expect(record.secret).to be_a(String)
        expect(record.secret).not_to be_empty
      end

      it 'still applies a call-site override to a defaulted column' do
        record = FactoryBakery.bake(model, state: 'published')

        expect(record.state).to eq('published')
      end
    end
  end

  describe '.bake!' do
    let!(:model) do
      define_model('PersistedRecord', name: :string, count: :integer) do
        validates :name, presence: true
      end
    end

    it 'persists the baked record' do
      record = FactoryBakery.bake!(model)

      expect(record).to be_persisted
      expect(model.find(record.id).name).to eq(record.name)
    end

    it 'honours call-site overrides when persisting' do
      record = FactoryBakery.bake!(model, name: 'known')

      expect(record.name).to eq('known')
      expect(record).to be_persisted
    end

    it 'leaves bake records unpersisted' do
      record = FactoryBakery.bake(model)

      expect(record).to be_new_record
      expect(model.count).to eq(0)
    end
  end
end
