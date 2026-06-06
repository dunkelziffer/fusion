# frozen_string_literal: true

# === CLI tools ===

require_relative "cli/parser"
require_relative "cli/serializer"

module Fusion
  module CLI
    # returns a runtime value
    def self.parse(json)
      Parser.parse(json)
    end

    # returns [exit_code, json]
    def self.serialize(runtime_value)
      Serializer.to_json(runtime_value)
    end
  end
end
