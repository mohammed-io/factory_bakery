# frozen_string_literal: true

require 'spec_helper'

# A stand-in for Mastodon's Remotable: assigning a remote URL downloads it, so
# the writer refuses anything but a blank value and records every assignment it
# receives, which lets each example prove the gem left it alone.
module RemoteUrlWriterSpec
  def remote_url_assignments
    @remote_url_assignments ||= []
  end

  def avatar_remote_url
    self[:avatar_remote_url]
  end

  def avatar_remote_url=(value)
    remote_url_assignments << value
    raise "remote URL writer received #{value.inspect}" unless value.blank?

    self[:avatar_remote_url] = value
  end
end

# A remote-URL writer downloads what it is handed (`avatar_remote_url=`,
# `header_remote_url=`, ...), so heuristics must never give one a value: a bake
# would open a socket and usually fail. These specs cover a nullable column, a
# NOT NULL column with and without a default, a presence-validated virtual
# writer, the name family, and an explicit override.
RSpec.describe 'remote URL writers are never filled' do
  include DefineConstantMacros

  def define_remotable(name, columns)
    define_model(name, columns) { include RemoteUrlWriterSpec }
  end

  it 'leaves a nullable remote URL column nil without calling its writer' do
    model = define_remotable('RemoteAvatarProfile', avatar_remote_url: :string)

    record = FactoryBakery.bake(model, fill_optional: true)

    expect(record.avatar_remote_url).to be_nil
    expect(record.remote_url_assignments).to be_empty
  end

  it 'leaves a nullable remote URL column nil on bake! too' do
    model = define_remotable('RemoteAvatarPersisted', avatar_remote_url: :string)

    record = FactoryBakery.bake!(model, fill_optional: true)

    expect(record).to be_persisted
    expect(record.avatar_remote_url).to be_nil
    expect(record.remote_url_assignments).to be_empty
    expect(model.find(record.id).avatar_remote_url).to be_nil
  end

  it 'keeps the default of a NOT NULL remote URL column' do
    model = define_remotable(
      'RemoteAvatarDefault',
      avatar_remote_url: { type: :string, null: false, default: 'https://cdn.example.com/keep.png' }
    )

    record = FactoryBakery.bake!(model, fill_optional: true)

    expect(record.avatar_remote_url).to eq('https://cdn.example.com/keep.png')
    expect(record.remote_url_assignments).to be_empty
  end

  it 'gives a NOT NULL remote URL column without a default an empty string' do
    model = define_remotable('RemoteAvatarRequired', avatar_remote_url: { type: :string, null: false })

    record = FactoryBakery.bake!(model, fill_optional: true)

    expect(record.avatar_remote_url).to eq('')
    expect(record.remote_url_assignments).to all(be_blank)
    expect(model.find(record.id).avatar_remote_url).to eq('')
  end

  it 'leaves a presence-validated virtual remote URL writer unset' do
    model = define_model('RemoteAvatarVirtual', name: :string) do
      attr_reader :avatar_remote_url

      def remote_url_assignments
        @remote_url_assignments ||= []
      end

      def avatar_remote_url=(value)
        remote_url_assignments << value
        raise "remote URL writer received #{value.inspect}" unless value.blank?

        @avatar_remote_url = value
      end

      validates :avatar_remote_url, presence: true
    end

    record = FactoryBakery.bake(model, fill_optional: true)

    expect(record.remote_url_assignments).to be_empty
    expect(record.avatar_remote_url).to be_nil
  end

  it 'still assigns an explicit override' do
    model = define_model('RemoteAvatarOverride', avatar_remote_url: :string) do
      def remote_url_assignments
        @remote_url_assignments ||= []
      end

      def avatar_remote_url=(value)
        remote_url_assignments << value
        super
      end
    end

    record = FactoryBakery.bake(model, avatar_remote_url: 'https://cdn.example.com/given.png')

    expect(record.avatar_remote_url).to eq('https://cdn.example.com/given.png')
    expect(record.remote_url_assignments.uniq).to eq(['https://cdn.example.com/given.png'])
  end

  it 'recognizes the remote URL name family and nothing else' do
    model = define_model(
      'RemoteNameFamily',
      avatar_remote_url: :string, remote_url: :string, remote_avatar_url: :string,
      avatar_url: :string, remote_thing: :string
    )
    guarded = %w[avatar_remote_url remote_url remote_avatar_url]
    ordinary = %w[avatar_url remote_thing]

    guarded.each do |name|
      constraints = FactoryBakery::ConstraintSet.for(model, name)
      filler = FactoryBakery::AttributeFillers::FillerSelector.new(model, name).call

      expect(constraints.guarded_writer).to be(true), "#{name} should be guarded"
      expect(filler).to be_a(FactoryBakery::AttributeFillers::NoopFiller), "#{name} should be left alone"
    end

    ordinary.each do |name|
      constraints = FactoryBakery::ConstraintSet.for(model, name)
      filler = FactoryBakery::AttributeFillers::FillerSelector.new(model, name).call

      expect(constraints.guarded_writer).to be(false), "#{name} should not be guarded"
      expect(filler).not_to be_a(FactoryBakery::AttributeFillers::NoopFiller), "#{name} should be filled"
    end
  end
end
