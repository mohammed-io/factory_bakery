# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'uniqueness enforcement (issue #33)' do
  include DefineConstantMacros

  describe 'repeated bakes of a plain unique string column' do
    let!(:model) do
      define_model('UniqueCode', code: :string) do
        validates :code, uniqueness: true
      end
    end

    it 'produces two distinct persisted records by regenerating on collision' do
      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'alpha', 'beta', 'gamma')

      first = FactoryBakery.bake!(model, fill_optional: true)
      second = FactoryBakery.bake!(model, fill_optional: true)

      expect(first.code).to eq('alpha')
      expect(second.code).to eq('beta')
      expect(first.code).not_to eq(second.code)
      expect(first).to be_persisted
      expect(second).to be_persisted
      expect(model.count).to eq(2)
      expect(first).to be_valid
      expect(second).to be_valid
    end
  end

  # Issue #51 switched the examples above to the opt-in because they assert
  # column values. Uniqueness is a nil-rejecting validator, so the same cases
  # must also hold on the default path with no fill_optional at all.
  describe 'default path (no fill_optional)' do
    let!(:model) do
      define_model('DefaultUniqueCode', code: :string) do
        validates :code, uniqueness: true
      end
    end

    it 'fills the nullable column and regenerates a collision' do
      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'alpha', 'beta')

      first = FactoryBakery.bake!(model)
      second = FactoryBakery.bake!(model)

      expect(first.code).to eq('alpha')
      expect(second.code).to eq('beta')
      expect([first, second]).to all(be_persisted)
      expect(model.count).to eq(2)
    end

    it 'raises the contextual error when the value space is exhausted' do
      forced = define_model('DefaultForcedUniqueCode', code: :string) do
        validates :code, inclusion: { in: ['FIXED'] }, uniqueness: true
      end
      FactoryBakery.bake!(forced)

      expect { FactoryBakery.bake!(forced) }
        .to raise_error(FactoryBakery::Error, /DefaultForcedUniqueCode#code.*FIXED/m)
    end

    it 'sees rows written outside the bake' do
      model.create!(code: 'alpha')
      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'beta')

      expect(FactoryBakery.bake!(model).code).to eq('beta')
    end

    it 'honours a uniqueness scope' do
      scoped = define_model('DefaultScopedUniqueCode', code: :string, account_id: :integer) do
        validates :code, uniqueness: { scope: :account_id }
      end
      allow(FFaker::Lorem).to receive(:word).and_return('same', 'same', 'fresh')

      first = FactoryBakery.bake!(scoped, account_id: 1)
      other_scope = FactoryBakery.bake!(scoped, account_id: 2)
      same_scope = FactoryBakery.bake!(scoped, account_id: 1)

      expect([first.code, other_scope.code]).to eq(%w[same same])
      expect(same_scope.code).to eq('fresh')
    end
  end

  describe 'a constrained value space (the audit forced-value probe)' do
    let!(:model) do
      define_model('ForcedUniqueCode', code: :string) do
        validates :code, inclusion: { in: ['FIXED'] }, uniqueness: true
      end
    end

    it 'raises a clear FactoryBakery::Error on the second bake, naming the attribute and constraint' do
      first = FactoryBakery.bake!(model, fill_optional: true)
      expect(first.code).to eq('FIXED')

      expect { FactoryBakery.bake!(model, fill_optional: true) }
        .to raise_error(FactoryBakery::Error, /ForcedUniqueCode#code.*FIXED.*attempts.*Uniqueness/m)

      expect(model.count).to eq(1)
    end

    it 'does not surface as an ActiveRecord::RecordInvalid' do
      FactoryBakery.bake!(model, fill_optional: true)

      expect { FactoryBakery.bake!(model, fill_optional: true) }.to raise_error(FactoryBakery::Error)
    end
  end

  describe 'DB-awareness' do
    let!(:model) do
      define_model('ExternalUniqueCode', code: :string) do
        validates :code, uniqueness: true
      end
    end

    it 'sees values inserted by other writes, not just by this bake' do
      model.create!(code: 'alpha')
      allow(FFaker::Lorem).to receive(:word).and_return('alpha', 'beta')

      record = FactoryBakery.bake!(model, fill_optional: true)

      expect(record.code).to eq('beta')
      expect(record).to be_persisted
    end
  end

  describe 'scope:' do
    let!(:model) do
      define_model('ScopedUniqueCode', code: :string, account_id: :integer) do
        validates :code, uniqueness: { scope: :account_id }
      end
    end

    it 'allows the same value in a different scope but regenerates within the same scope' do
      allow(FFaker::Lorem).to receive(:word).and_return('same', 'same', 'same', 'fresh')

      first = FactoryBakery.bake!(model, account_id: 1, fill_optional: true)
      other_scope = FactoryBakery.bake!(model, account_id: 2, fill_optional: true)
      same_scope = FactoryBakery.bake!(model, account_id: 1, fill_optional: true)

      expect(first.code).to eq('same')
      expect(other_scope.code).to eq('same')
      expect(same_scope.code).to eq('fresh')
    end

    it 'accepts an array of scope columns' do
      multi = define_model('MultiScopedUniqueCode', code: :string, account_id: :integer, kind: :string) do
        validates :code, uniqueness: { scope: %i[account_id kind] }
      end
      allow(FFaker::Lorem).to receive(:word).and_return('same', 'same', 'same', 'different_scope')

      one = FactoryBakery.bake!(multi, account_id: 1, kind: 'a', fill_optional: true)
      same_scopes = FactoryBakery.bake!(multi, account_id: 1, kind: 'a', fill_optional: true)

      expect(one.code).to eq('same')
      expect(same_scopes.code).to eq('different_scope')
    end
  end

  describe 'case_sensitive: false' do
    it 'treats case variants as a collision' do
      model = define_model('CaseInsensitiveUniqueCode', code: :string) do
        validates :code, inclusion: { in: %w[Token TOKEN] }, uniqueness: { case_sensitive: false }
      end
      model.new(code: 'token').save!(validate: false)

      expect { FactoryBakery.bake!(model, fill_optional: true) }
        .to raise_error(FactoryBakery::Error, /CaseInsensitiveUniqueCode#code/)
    end

    it 'still allows case variants when case_sensitive is true' do
      model = define_model('CaseSensitiveUniqueCode', code: :string) do
        validates :code, inclusion: { in: ['Token'] }, uniqueness: { case_sensitive: true }
      end
      model.new(code: 'token').save!(validate: false)

      record = FactoryBakery.bake!(model, fill_optional: true)

      expect(record.code).to eq('Token')
      expect(record).to be_persisted
    end
  end
end
