# frozen_string_literal: true

require_relative "lib/fusion/version"

Gem::Specification.new do |spec|
  spec.name = "fusion-lang"
  spec.version = Fusion::VERSION
  spec.authors = ["Klaus Weidinger"]
  spec.email = ["weidkl@gmx.de"]
  spec.license = "MIT"

  spec.summary = "A JSON-inspired functional programming language "
  spec.description = spec.summary
  spec.homepage = "https://github.com/dunkelziffer/fusion"

  spec.metadata = {
    "source_code_uri"       => spec.homepage,
    "homepage_uri"          => spec.homepage,
    # "changelog_uri"         => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "bug_tracker_uri"       => "#{spec.homepage}/issues",
    "documentation_uri"     => "#{spec.homepage}/blob/main/README.md",
    "rubygems_mfa_required" => "true",
  }

  # === CONTENTS ===

  gemspec = File.basename(__FILE__)
  spec.files = `git ls-files`
    .split("\n")
    .reject { |f| File.symlink?(f) }
    .reject { |f| f == gemspec }
    .reject { |f| f.start_with?('.github/', 'bin/', 'spec/', '.gem_release.yml', '.gitignore', '.rspec', '.rubocop.yml', '.rubocop_todo.yml', '.ruby-version', 'Gemfile', 'Gemfile.lock', 'RELEASING.md') }
  spec.require_paths = ["lib"]

  spec.bindir = "exe"
  spec.executables = ["fusion"]

  # === DEPENDENCIES ===

  spec.required_ruby_version = ">= 3.3.0"
end
