# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

# task :spec (skips slow files, see .rspec)
RSpec::Core::RakeTask.new(:spec)

namespace :spec do
  # task :all
  desc "Run all specs, including the slow ones (real binary / pty)"
  RSpec::Core::RakeTask.new(:all) do |task|
    task.rspec_opts = "--options .rspec-ci"
  end
end

task default: :spec
