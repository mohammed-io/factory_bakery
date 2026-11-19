# frozen_string_literal: true

module FactoryBakery
  module Attachments
    # One bundled fixture: a tiny real file with a known content type. The
    # bytes are read once and memoized, while every attachable gets a fresh
    # IO over them because an attachable consumes its stream.
    class Fixture
      attr_reader :content_type, :filename, :path

      def initialize(content_type, filename)
        @content_type = content_type
        @filename = filename
        @path = File.expand_path(File.join('fixtures', filename), __dir__)
      end

      def extension
        File.extname(filename).delete_prefix('.')
      end

      # A fresh IO on every call: attachables read the stream to the end.
      def io
        StringIO.new(bytes)
      end

      # The filename an attachment is given: its own name plus the extension
      # that matches the bytes, so an extension-based check agrees with the
      # content type.
      def filename_for(name)
        "#{name}.#{extension}"
      end

      private

      def bytes
        @bytes ||= File.binread(path)
      end
    end
  end
end
