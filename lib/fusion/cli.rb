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

    # returns JSON
    def self.serialize(runtime_value)
      Serializer.to_json(runtime_value)
    end

    # whether a value can be faithfully emitted as a program result
    def self.serializable?(runtime_value)
      Serializer.serializable?(runtime_value)
    end
  end
end
