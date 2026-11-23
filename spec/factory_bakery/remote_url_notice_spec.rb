# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

# A remote-URL writer is left blank on purpose, because assigning it downloads
# the URL. The gem says so once per model and attribute, unless the caller
# supplied the value.
RSpec.describe 'a remote URL left blank on purpose is announced' do
  let(:log) { StringIO.new }

  before do
    FactoryBakery.logger = Logger.new(log, formatter: FactoryBakery::Seed::LOG_FORMAT)
  end

  after do
    FactoryBakery.logger = Logger.new(nil)
  end

  def announcement(model_name)
    "WARN: left #{model_name}#avatar_remote_url blank on purpose: assigning it downloads the URL. " \
      'Set it in a definition or pass it as an override to fill it.'
  end

  it 'warns once across several bakes of the same model' do
    model = define_model('RemoteNoticeProfile', avatar_remote_url: :string)

    FactoryBakery.bake(model)
    FactoryBakery.bake(model)

    expect(log.string.scan(announcement('RemoteNoticeProfile')).size).to eq(1)
  end

  it 'stays silent when the caller passes the value as an override' do
    model = define_model('RemoteNoticeOverridden', avatar_remote_url: :string)

    record = FactoryBakery.bake(model, avatar_remote_url: 'https://cdn.example.com/given.png')

    expect(record.avatar_remote_url).to eq('https://cdn.example.com/given.png')
    expect(log.string).to be_empty
  end

  it 'stays silent when a definition declares the value' do
    model = define_model('RemoteNoticeDefined', avatar_remote_url: :string)
    FactoryBakery.define(model) { avatar_remote_url { 'https://cdn.example.com/defined.png' } }

    FactoryBakery.bake(model)

    expect(log.string).to be_empty
  end

  it 'stays silent when a definition skips the writer on purpose' do
    model = define_model('RemoteNoticeSkipped', avatar_remote_url: :string)
    FactoryBakery.define(model) { skip :avatar_remote_url }

    FactoryBakery.bake(model)

    expect(log.string).to be_empty
  end

  it 'stays silent when the column keeps a non-blank default' do
    model = define_model(
      'RemoteNoticeDefaulted',
      avatar_remote_url: { type: :string, null: false, default: 'https://cdn.example.com/keep.png' }
    )

    FactoryBakery.bake(model)

    expect(log.string).to be_empty
  end

  it 'bakes without error when the logger is silenced' do
    model = define_model('RemoteNoticeSilenced', avatar_remote_url: :string)
    FactoryBakery.logger = nil

    expect(FactoryBakery.bake(model)).to be_a(model)
  end
end
