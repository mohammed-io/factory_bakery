# frozen_string_literal: true

require 'spec_helper'
require 'open3'

# Requiring the gem must not load ActiveRecord::Base itself: the host app owns
# when its ORM finishes booting, and touching the class early runs Rails'
# `on_load(:active_record)` hooks too soon (Active Record encryption, for one,
# then reads the app's settings before they exist). The examples run in a
# subprocess that starts clean, because this spec process has ActiveRecord
# loaded long before the gem — the very order the suite cannot reproduce.
RSpec.describe 'load order' do
  def capture_ruby(code)
    Open3.capture3(
      RbConfig.ruby,
      '-I', File.expand_path('../../lib', __dir__),
      '-e', code
    )
  end

  it 'does not load ActiveRecord::Base when the gem is required' do
    code = <<~RUBY
      require 'logger'
      require 'active_record'
      require 'factory_bakery'
      print ActiveRecord.autoload?(:Base).inspect
    RUBY

    stdout, stderr, status = capture_ruby(code)

    expect(status).to be_success, "subprocess failed:\n#{stderr}\n#{stdout}"
    expect(stdout).not_to eq('nil')
  end

  it 'installs the schema-reload hook once ActiveRecord::Base loads' do
    code = <<~RUBY
      require 'logger'
      require 'active_record'
      require 'factory_bakery'
      print ActiveRecord::Base.singleton_class.ancestors
        .include?(FactoryBakery::ActiveRecordMapper::SchemaReload).inspect
    RUBY

    stdout, stderr, status = capture_ruby(code)

    expect(status).to be_success, "subprocess failed:\n#{stderr}\n#{stdout}"
    expect(stdout).to eq('true')
  end
end
