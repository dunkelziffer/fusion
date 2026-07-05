# frozen_string_literal: true

# Central SimpleCov configuration, shared by
# - the in-process suite (spec/spec_helper.rb)
# - the subprocesses spawned to drive the real binary (spec/simplecov_spawn.rb)
SimpleCov.configure do
  enable_coverage :branch

  add_group "Fusion", "lib/"
  add_group "Tests", "spec/"
end
