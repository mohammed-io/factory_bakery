# frozen_string_literal: true

# The Active Storage plumbing a host application normally boots, loaded
# directly instead of booting a Rails app: the attachment model mixin, the
# reflection extension, the service registry and the blob/attachment models.
# Each spec that needs it then configures the Disk service and creates the
# Active Storage tables on the in-memory connection.
#
# Guarded so a suite that loads it from more than one spec file sets it up
# once (Zeitwerk refuses two loaders over the same model directory).
unless defined?(ActiveStorage::Blob)
  require 'active_storage'
  require 'active_storage/attached'
  require 'active_storage/reflection'
  require 'active_storage/service'
  require 'active_storage/service/registry'
  require 'zeitwerk'

  ActiveRecord::Base.include(ActiveStorage::Reflection::ActiveRecordExtensions)
  ActiveRecord::Reflection.singleton_class.prepend(ActiveStorage::Reflection::ReflectionExtension)
  ActiveRecord::Base.include(ActiveStorage::Attached::Model)

  # The engine's isolate_namespace equivalent: without it the blob and
  # attachment models would look for tables named `blobs` and `attachments`.
  ActiveStorage.define_singleton_method(:table_name_prefix) { 'active_storage_' }

  loader = Zeitwerk::Loader.new
  loader.push_dir(File.join(Gem::Specification.find_by_name('activestorage').gem_dir, 'app/models'))
  loader.setup
  loader.eager_load
end

# Creates the Active Storage tables on the current connection. Available to
# every spec that boots Active Storage.
module ActiveStorageSpecSupport
  module_function

  def create_tables!
    create_blob_tables!
    create_attachment_tables!
  end

  def create_blob_tables!
    connection = ActiveRecord::Base.connection
    connection.drop_table(:active_storage_blobs, if_exists: true)
    connection.create_table(:active_storage_blobs) do |table|
      table.string :key, null: false
      table.string :filename, null: false
      table.string :content_type
      table.text :metadata
      table.string :service_name, null: false
      table.bigint :byte_size, null: false
      table.string :checksum
      table.timestamps
    end
  end

  def create_attachment_tables!
    connection = ActiveRecord::Base.connection
    connection.drop_table(:active_storage_attachments, if_exists: true)
    connection.create_table(:active_storage_attachments) do |table|
      table.string :name, null: false
      table.string :record_type, null: false
      table.bigint :record_id
      table.bigint :blob_id, null: false
      table.timestamps
    end

    connection.drop_table(:active_storage_variant_records, if_exists: true)
    connection.create_table(:active_storage_variant_records) do |table|
      table.bigint :blob_id, null: false
      table.string :variation_digest, null: false
    end
  end
end
