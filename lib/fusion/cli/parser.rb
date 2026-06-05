# frozen_string_literal: true

# === CLI internals ===
#
# Input: JSON
# Output: Interpreter runtime value

require "json"

module Fusion
  module CLI
    module Parser
      extend self

      def parse(json)
        ruby_value = JSON.parse(json)
        convert(ruby_value)
      rescue JSON::ParserError
        Interpreter::ErrorVal.internal(kind: "parse_error", location: "input", operation: "parsing input as JSON",
                    input: json, message: "input is not valid JSON")
      end

      private

      # returns a runtime value
      def convert(ruby_value)
        case ruby_value
        when nil then Interpreter::NULL
        when Array then ruby_value.map { |item| convert(item) }
        when Hash then ruby_value.transform_values { |value| convert(value) }
        else ruby_value
        end
      end
    end
  end
end
