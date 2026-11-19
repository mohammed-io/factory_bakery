# frozen_string_literal: true

require 'spec_helper'
require_relative '../support/active_storage_boot'
require 'fileutils'
require 'open3'
require 'tmpdir'

# Stand-ins for the optional attachment libraries, which are deliberately not
# bundle dependencies. Each declares the same validators and options the real
# library sets, so the plugin reads them exactly as it would in an application
# that has the gem installed.
module ActiveStorageValidations
  class ContentTypeValidator < ActiveModel::EachValidator
    def validate_each(record, attribute, _value)
      attachment = record.public_send(attribute)
      return unless attachment.attached?

      types = Array(options[:content_type] || options[:with] || options[:in])
      return if types.include?(attachment.content_type)

      record.errors.add(attribute, :content_type_invalid)
    end
  end
end
ActiveRecord::Base.include(ActiveStorageValidations)

module Paperclip
  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def attachment_definitions
      @attachment_definitions ||= {}
    end

    def has_attached_file(name, options = {})
      attachment_definitions[name.to_s] = options
      attr_accessor(name)
    end

    def validates_attachment_presence(name, options = {})
      validates_with(Paperclip::Validators::AttachmentPresenceValidator, attributes: [name], **options)
    end

    def validates_attachment_content_type(name, options = {})
      validates_with(Paperclip::Validators::AttachmentContentTypeValidator, attributes: [name], **options)
    end
  end

  module Validators
    class AttachmentPresenceValidator < ActiveModel::EachValidator
      def validate_each(record, attribute, _value)
        record.errors.add(attribute, :blank) if record.public_send(attribute).nil?
      end
    end

    # The content type a real Paperclip attachment derives from its file; the
    # extension is the only signal the stand-in reads.
    class AttachmentContentTypeValidator < ActiveModel::EachValidator
      EXTENSION_TYPES = {
        'png' => 'image/png', 'jpg' => 'image/jpeg', 'jpeg' => 'image/jpeg',
        'gif' => 'image/gif', 'webp' => 'image/webp', 'mp4' => 'video/mp4',
        'mp3' => 'audio/mpeg', 'pdf' => 'application/pdf', 'txt' => 'text/plain'
      }.freeze

      def validate_each(record, attribute, _value)
        file = record.public_send(attribute)
        return if file.nil?

        extension = File.extname(file.path.to_s).delete_prefix('.')
        content_type = EXTENSION_TYPES.fetch(extension, 'application/octet-stream')
        return if Array(options[:content_type]).include?(content_type)

        record.errors.add(attribute, :content_type_invalid)
      end
    end
  end
end

require 'factory_bakery'
require 'factory_bakery/attachments'

RSpec.describe 'FactoryBakery attachments plugin' do
  include DefineConstantMacros

  before do
    FactoryBakery.reset_plugins!
    FactoryBakery.register_plugin(FactoryBakery::Attachments::Plugin)

    @disk_root = Dir.mktmpdir('factory_bakery-attachments-')
    ActiveStorage::Blob.services = ActiveStorage::Service::Registry.new(
      test: { service: 'Disk', root: @disk_root }
    )
    ActiveStorageSpecSupport.create_tables!
  end

  after do
    FactoryBakery.reset_plugins!
    FileUtils.remove_entry(@disk_root)
  end

  def fixture_bytes(name)
    File.binread(File.expand_path("../../lib/factory_bakery/attachments/fixtures/#{name}", __dir__))
  end

  describe 'Active Storage' do
    it 'attaches a PNG to a required attachment' do
      model = define_model('AttachmentsAvatarUser', name: :string) do
        has_one_attached :avatar, service: :test
        validates :avatar, presence: true
      end

      record = FactoryBakery.bake(model)

      expect(record.avatar.attached?).to be(true)
      expect(record.avatar.filename.to_s).to eq('avatar.png')
      expect(record.avatar.content_type).to eq('image/png')
      expect(record).to be_valid
    end

    it 'persists the blob, the attachment row and the file with bake!' do
      model = define_model('AttachmentsPersistedUser', name: :string) do
        has_one_attached :avatar, service: :test
        validates :avatar, presence: true
      end

      record = FactoryBakery.bake!(model)

      expect(record).to be_persisted
      expect(record.reload.avatar.attached?).to be(true)
      expect(record.avatar.blob).to be_persisted
      expect(record.avatar.blob.content_type).to eq('image/png')
      expect(record.avatar.blob.byte_size).to eq(fixture_bytes('png.png').bytesize)
      expect(record.avatar.download).to eq(fixture_bytes('png.png'))
    end

    it 'uses a JPEG fixture when the attachment only allows image/jpeg' do
      model = define_model('AttachmentsJpegUser', name: :string) do
        has_one_attached :avatar, service: :test
        validates :avatar, presence: true
        validates :avatar, content_type: ['image/jpeg']
      end

      record = FactoryBakery.bake(model)

      expect(record.avatar.content_type).to eq('image/jpeg')
      expect(record.avatar.filename.to_s).to eq('avatar.jpg')
      expect(record).to be_valid
    end

    it 'matches wildcard and Regexp content-type rules' do
      wildcard = define_model('AttachmentsWildcardUser', name: :string) do
        has_one_attached :avatar, service: :test
        validates :avatar, presence: true, content_type: ['image/*']
      end
      regexp = define_model('AttachmentsRegexpUser', name: :string) do
        has_one_attached :avatar, service: :test
        validates :avatar, presence: true, content_type: [%r{\Aimage/gif\z}]
      end

      expect(FactoryBakery.bake(wildcard).avatar.content_type).to eq('image/png')
      expect(FactoryBakery.bake(regexp).avatar.content_type).to eq('image/gif')
    end

    it 'raises a clear error when no bundled fixture matches the allowed types' do
      model = define_model('AttachmentsTiffUser', name: :string) do
        has_one_attached :avatar, service: :test
        validates :avatar, presence: true, content_type: ['image/tiff']
      end

      expect { FactoryBakery.bake(model) }
        .to raise_error(FactoryBakery::Error, /no bundled attachment fixture matches/)
    end

    it 'leaves an optional attachment empty by default' do
      model = define_model('AttachmentsOptionalUser', name: :string) do
        has_one_attached :avatar, service: :test
      end

      expect(FactoryBakery.bake(model).avatar.attached?).to be(false)
    end

    it 'fills an optional attachment when fill_optional asks for it' do
      model = define_model('AttachmentsOptionalFillUser', name: :string) do
        has_one_attached :avatar, service: :test
      end

      expect(FactoryBakery.bake(model, fill_optional: true).avatar.attached?).to be(true)
      expect(FactoryBakery.bake(model, fill_optional: %i[avatar]).avatar.attached?).to be(true)
    end

    it 'honours skip, declarations and call-site overrides' do
      model = define_model('AttachmentsSkippedUser', name: :string) do
        has_one_attached :avatar, service: :test
        validates :avatar, presence: true
      end
      FactoryBakery.define(model) { skip :avatar }

      expect(FactoryBakery.bake(model).avatar.attached?).to be(false)
      expect(FactoryBakery.bake(model, avatar: nil).avatar.attached?).to be(false)
    end

    it 'honours if:/unless: guards on the presence rule' do
      model = define_model('AttachmentsGuardedUser', name: :string) do
        attr_accessor :skip_avatar

        has_one_attached :avatar, service: :test
        validates :avatar, presence: true, unless: :skip_avatar
      end

      expect(FactoryBakery.bake(model).avatar.attached?).to be(true)
      expect(FactoryBakery.bake(model, skip_avatar: true).avatar.attached?).to be(false)
    end
  end

  describe 'Paperclip' do
    it 'fills a required attachment with the default PNG' do
      model = define_model('PaperclipAvatarUser', name: :string) do
        include Paperclip
        has_attached_file :avatar
        validates_attachment_presence :avatar
      end

      record = FactoryBakery.bake(model)

      expect(record.avatar).to be_a(File)
      expect(File.extname(record.avatar.path)).to eq('.png')
      expect(record).to be_valid
    end

    it 'picks a fixture that matches the allowed content type' do
      model = define_model('PaperclipCoverUser', name: :string) do
        include Paperclip
        has_attached_file :cover
        validates_attachment_presence :cover
        validates_attachment_content_type :cover, content_type: ['image/jpeg']
      end

      record = FactoryBakery.bake(model)

      expect(File.extname(record.cover.path)).to eq('.jpg')
      expect(record).to be_valid
    end

    it 'leaves an optional attachment empty' do
      model = define_model('PaperclipOptionalUser', name: :string) do
        include Paperclip
        has_attached_file :avatar
      end

      expect(FactoryBakery.bake(model).avatar).to be_nil
    end
  end

  it 'is opt-in: the core never registers the plugin, the require does' do
    ffaker_lib = File.join(Gem::Specification.find_by_name('ffaker').gem_dir, 'lib')
    code = <<~RUBY
      require 'factory_bakery'

      abort 'the core must not register the attachments plugin' unless
        FactoryBakery::PluginRegistry.plugins.empty?

      require 'factory_bakery/attachments'

      abort 'the require must register the attachments plugin' unless
        FactoryBakery::PluginRegistry.plugins.include?(FactoryBakery::Attachments::Plugin)

      print 'OK'
    RUBY

    stdout, stderr, status = nil
    Bundler.with_unbundled_env do
      stdout, stderr, status = Open3.capture3(
        RbConfig.ruby, '-I', ffaker_lib, '-I', File.expand_path('../../lib', __dir__), '-e', code
      )
    end

    expect(status).to be_success, "opt-in check failed:\n#{stderr}\n#{stdout}"
    expect(stdout).to eq('OK')
  end

  it 'leaves an attachment alone when the plugin is not registered' do
    FactoryBakery.unregister_plugin(FactoryBakery::Attachments::Plugin)
    model = define_model('AttachmentsUnaffectedUser', name: :string) do
      has_one_attached :avatar, service: :test
    end

    expect(FactoryBakery.bake(model).avatar.attached?).to be(false)
  end
end
