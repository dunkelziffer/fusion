# frozen_string_literal: true

# Preloaded (via `ruby -r`) into every subprocess when `ENV["COVERAGE"]` is set.
# Not in `spec/support/` on purpose. `spec_helper.rb` requires everything there
# into the parent process, where the `at_fork` call would clobber its setup.
require "simplecov"

# Some specs spawn with another working directory
SimpleCov.root File.expand_path("..", __dir__)

# `require "simplecov"` only auto-loads the shared config in `.simplecov` if the
# working directory is inside the project, so load it explicitly. Idempotent.
load File.join(SimpleCov.root, ".simplecov")

SimpleCov.command_name "exe/fusion"
SimpleCov.at_fork.call(Process.pid)
