# frozen_string_literal: true

require 'spec_helper'
require_relative '../support/active_storage_boot'
require 'fileutils'
require 'tmpdir'

# Review findings for the attachments plugin: a plugin-less `bake` must not
# raise on an Active Storage model whose attachment is presence-validated
# (#57's virtual-attribute universe must leave attachment reflections alone),
# and the plugin must resolve if:/unless: with the mapper's semantics so a
# private predicate works in both directions.
#
# `factory_bakery/attachments` is deliberately required only in the examples
# that register the plugin, so the plugin-less examples run exactly as an
# application that never loaded it (the plugin registry is reset around every
# example, which also clears it when a sibling spec file loaded it).
RSpec.describe 'FactoryBakery attachments review' do
  include DefineConstantMacros

  before do
    FactoryBakery.reset_plugins!

    @disk_root = Dir.mktmpdir('factory_bakery-attachments-review-')
    ActiveStorage::Blob.services = ActiveStorage::Service::Registry.new(
      test: { service: 'Disk', root: @disk_root }
    )
    ActiveStorageSpecSupport.create_tables!
  end

  after do
    FactoryBakery.reset_plugins!
    FileUtils.remove_entry(@disk_root)
  end

  describe 'without the attachments plugin' do
    it 'bakes an Active Storage model with a presence-validated attachment' do
      model = define_model('AttachmentsReviewBareUser', name: :string) do
        has_one_attached :avatar, service: :test
        validates :avatar, presence: true
      end

      record = FactoryBakery.bake(model)

      expect(record.avatar.attached?).to be(false)
    end

    it 'bakes a private-predicate-guarded presence rule in both directions' do
      model = define_model('AttachmentsReviewBareGuardUser', name: :string) do
        attr_accessor :wants_avatar

        has_one_attached :avatar, service: :test
        validates :avatar, presence: true, if: :needs_avatar?

        def needs_avatar?
          wants_avatar
        end
        private :needs_avatar?
      end

      expect(FactoryBakery.bake(model, wants_avatar: true).avatar.attached?).to be(false)
      expect(FactoryBakery.bake(model, wants_avatar: false).avatar.attached?).to be(false)
    end
  end

  describe 'with the attachments plugin' do
    before do
      require 'factory_bakery/attachments'
      FactoryBakery.register_plugin(FactoryBakery::Attachments::Plugin)
    end

    it 'attaches a fixture to a required attachment' do
      model = define_model('AttachmentsReviewPluginUser', name: :string) do
        has_one_attached :avatar, service: :test
        validates :avatar, presence: true
      end

      record = FactoryBakery.bake(model)

      expect(record.avatar.attached?).to be(true)
      expect(record.avatar.filename.to_s).to eq('avatar.png')
    end

    it 'honours a presence rule gated by a private predicate in both directions' do
      model = define_model('AttachmentsReviewPrivateGuardUser', name: :string) do
        attr_accessor :wants_avatar

        has_one_attached :avatar, service: :test
        validates :avatar, presence: true, if: :needs_avatar?

        def needs_avatar?
          wants_avatar
        end
        private :needs_avatar?
      end

      expect(FactoryBakery.bake(model, wants_avatar: true).avatar.attached?).to be(true)
      expect(FactoryBakery.bake(model, wants_avatar: false).avatar.attached?).to be(false)
    end
  end
end
