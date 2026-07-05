# frozen_string_literal: true

# Configured in `.simplecov`.
if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start
end

require_relative "../lib/fusion"

Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { |f| require f }

RSpec.configure do |config|
  config.include FusionHelpers

  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.disable_monkey_patching!
  config.order = :random
  Kernel.srand config.seed
end
