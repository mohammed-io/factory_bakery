# frozen_string_literal: true

require 'spec_helper'
require 'active_support/notifications'

# `FactoryBakery.validate` (and the per-call `validate:`) switches the gem's
# own checks off: the verified fallback's `valid?` probe and rebuild, the
# verification of optional fills, and the build-time uniqueness checks.
# Values are still generated from the validators and column types exactly as
# before; `bake!` still saves through the framework's normal validation.
RSpec.describe 'the validate option' do
  include DefineConstantMacros

  after { FactoryBakery.validate = nil }

  def selects_in
    statements = []
    subscriber = ActiveSupport::Notifications.subscribe('sql.active_record') do |*, payload|
      statements << payload[:sql] if payload[:sql].start_with?('SELECT') && payload[:name] != 'SCHEMA'
    end
    yield
    statements
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber)
  end

  # Prepends a counter on the model class, so `valid?` calls made by the gem
  # (the fallback probe and the optional-fill verification) are observable.
  # The count travels in a Hash so the caller reads the live count, not a
  # snapshot taken when the counter was installed.
  def valid_calls_in(model)
    calls = Hash.new(0)
    counter = Module.new do
      define_method(:valid?) do |*args, &block|
        calls[:count] += 1
        super(*args, &block)
      end
    end
    model.prepend(counter)
    calls
  end

  # A model the verified fallback must rebuild: a custom validate block
  # demands an optional column the heuristics leave nil on a lean build.
  def fallback_model(prefix)
    define_model("#{prefix}Nick", nickname: :string) do
      validate { errors.add(:nickname, :blank) if nickname.blank? }
    end
  end

  it 'is on by default' do
    expect(FactoryBakery.validate?).to be(true)
  end

  it 'returns a valid record by default, with the fallback having filled the optional column' do
    model = fallback_model('ValidateDefault')

    record = FactoryBakery.bake(model)

    expect(record).to be_valid
    expect(record.nickname).to be_present
  end

  describe 'validate: false on one bake' do
    it 'never calls valid? and returns the lean record' do
      model = fallback_model('ValidateOff')
      calls = valid_calls_in(model)

      record = FactoryBakery.bake(model, validate: false)

      expect(calls[:count]).to eq(0)
      expect(record.nickname).to be_nil
      expect(record.valid?).to be(false)
    end

    it 'issues no uniqueness SELECT, where the default issues one' do
      unique = define_model('ValidateUniqueCode', code: :string) do
        validates :code, uniqueness: true
      end

      expect(selects_in { FactoryBakery.bake(unique) }.size).to eq(1)
      expect(selects_in { FactoryBakery.bake(unique, validate: false) }).to be_empty
    end
  end

  describe 'the global setting' do
    it 'behaves like the per-call false' do
      model = fallback_model('ValidateGlobal')
      calls = valid_calls_in(model)

      FactoryBakery.validate = false
      record = FactoryBakery.bake(model)

      expect(calls[:count]).to eq(0)
      expect(record.nickname).to be_nil
    end

    it 'is beaten by a per-call true' do
      model = fallback_model('ValidateOverride')
      FactoryBakery.validate = false

      record = FactoryBakery.bake(model, validate: true)

      expect(record).to be_valid
      expect(FactoryBakery.validate?).to be(false)
    end

    it 'is set through configure and nil means true' do
      FactoryBakery.configure { |config| config.validate = false }
      expect(FactoryBakery.validate?).to be(false)

      FactoryBakery.validate = nil
      expect(FactoryBakery.validate?).to be(true)
    end
  end

  it 'reports the effective value inside a scoped bake' do
    probed = define_model('ValidateProbeModel', name: :string)
    observed = nil
    FactoryBakery.define(probed) do
      observed = FactoryBakery.validate?
      name { 'probe' }
    end

    FactoryBakery.bake(probed, validate: false)

    expect(observed).to be(false)
  end

  it 'inherits validate: false in a nested bake made by a definition block' do
    validator = Class.new(ActiveModel::Validator) do
      def validate(record)
        return unless record.token.nil? && record.secret.nil?

        record.errors.add(:base, 'a credential must be selected')
      end
    end
    account = fallback_model('ValidateNested')
    child = define_model('ValidateNestedChild', token: :string, secret: :string) do
      attr_accessor :account

      validates_with validator
    end
    FactoryBakery.define(child) { account { FactoryBakery.bake(account) } }
    calls = valid_calls_in(account)

    record = FactoryBakery.bake(child, validate: false)

    expect(calls[:count]).to eq(0)
    expect(record.account.nickname).to be_nil
  end

  it 'still raises on bake! of a record that is invalid, and persists a valid one' do
    model = fallback_model('ValidateBang')

    expect { FactoryBakery.bake!(model, validate: false) }.to raise_error(ActiveRecord::RecordInvalid)

    plain = define_model('ValidateBangPlain', name: :string) { validates :name, presence: true }
    expect(FactoryBakery.bake!(plain, validate: false)).to be_persisted
  end

  describe 'the override scope' do
    it 'restores the previous override after a nested scope that set none' do
      seen = []
      FactoryBakery::Verification.with(false) do
        FactoryBakery::Verification.with(nil) { seen << FactoryBakery.validate? }
        seen << FactoryBakery.validate?
      end

      expect(seen).to eq([false, false])
    end

    it 'keeps the outer validate: false across two consecutive nested bakes' do
      account = fallback_model('ValidateScopeAccount')
      child = define_model('ValidateScopeChild', name: :string)
      FactoryBakery.define(child) do
        FactoryBakery.bake(account)
        FactoryBakery.bake(account)
        name { 'child' }
      end
      calls = valid_calls_in(account)

      FactoryBakery.bake(child, validate: false)

      expect(calls[:count]).to eq(0)
    end

    it 'expires for a fiber created inside the bake and resumed after it' do
      model = fallback_model('ValidateFiberScope')
      observed = nil
      fiber = nil
      FactoryBakery.define(model) do
        fiber = Fiber.new { observed = FactoryBakery.validate? }
        name { 'x' }
      end

      FactoryBakery.bake(model, validate: false)
      fiber.resume

      expect(observed).to be(true)
      expect(FactoryBakery.validate?).to be(true)
    end
  end

  describe 'a non-boolean validate: value' do
    it 'travels as a plain attribute override for a target with a validate attribute' do
      policy = define_class('ValidateKeywordPoro') do
        attr_accessor :name, :validate
      end

      record = FactoryBakery.bake(policy, name: 'strict', validate: 'yes')

      expect(record.validate).to eq('yes')
      expect(record.name).to eq('strict')
      expect(FactoryBakery.validate?).to be(true)
    end

    it 'bakes! the same way' do
      policy = define_class('ValidateKeywordBangPoro') do
        attr_accessor :validate

        def save!
          self
        end
      end

      expect(FactoryBakery.bake!(policy, validate: 'pending').validate).to eq('pending')
    end

    it 'passes a fill_optional: value the keyword cannot act through as an override too' do
      model = define_class('FillOptionalKeywordPoro') do
        attr_accessor :name, :fill_optional
      end

      record = FactoryBakery.bake(model, name: 'full', fill_optional: 'everything')

      expect(record.fill_optional).to eq('everything')
    end

    it 'still validates the global setting' do
      expect { FactoryBakery.validate = 'yes' }
        .to raise_error(ArgumentError, 'validate must be true or false, got "yes"')
    end
  end
end
