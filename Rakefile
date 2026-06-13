# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

# Default suite. Reads .rspec, which excludes the `:slow` specs — the ones that
# shell out to the real `exe/fusion` (cli_spec) or drive a pty (repl_pty_spec).
RSpec::Core::RakeTask.new(:spec)

namespace :spec do
  # Full suite, including the slow specs. `--options .rspec-ci` makes RSpec read
  # .rspec-ci instead of .rspec, so the `--tag ~slow` exclusion is not applied.
  desc "Run all specs, including the slow ones (real binary / pty)"
  RSpec::Core::RakeTask.new(:all) do |task|
    task.rspec_opts = "--options .rspec-ci"
  end
end

task default: :spec
