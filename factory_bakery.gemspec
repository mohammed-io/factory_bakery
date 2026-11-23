# frozen_string_literal: true

require_relative 'lib/factory_bakery/version'

Gem::Specification.new do |spec|
  spec.name          = 'factory_bakery'
  spec.version       = FactoryBakery::VERSION
  spec.authors       = ['Mohammed A.']
  spec.email         = ['mohd@hey.com']

  spec.summary       = 'A gem that fill Active Record models with random/fake data'
  spec.description   = 'A gem that fill Active Record models with random/fake data'
  spec.homepage      = 'https://github.com/mohammed-io/factory_bakery'
  spec.license       = 'MIT'
  spec.required_ruby_version = Gem::Requirement.new('>= 3.2.0')

  spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = 'https://github.com/mohammed-io/factory_bakery'
  spec.metadata['changelog_uri'] = 'https://github.com/mohammed-io/factory_bakery/blob/main/CHANGELOG.md'

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    tracked = `git ls-files -z`.split("\x0")
    # The attachment fixtures are binary files, so they are listed explicitly
    # instead of relying on the tracked-file listing alone.
    fixtures = Dir['lib/factory_bakery/attachments/fixtures/*']
    (tracked + fixtures).uniq.reject { |f| f.match(%r{\A(?:test|spec|features)/}) }
  end
  spec.bindir        = 'exe'
  spec.executables   = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ['lib']

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, checkout our
  # guide at: https://bundler.io/guides/creating_gem.html

  # Production
  spec.add_dependency 'ffaker'
  # FactoryBakery.logger defaults to a stdlib Logger; Ruby 4.0 no longer ships
  # logger as a default gem.
  spec.add_dependency 'logger'
  spec.add_dependency 'regexp_parser', '~> 2.9'

  # Development
  spec.add_development_dependency 'appraisal'
end
