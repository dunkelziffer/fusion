# frozen_string_literal: true

# === CLI internals ===

require "json"

module Fusion
  module CLI
    module Parser
      extend self

      # WirePair -> runtime value
      def parse(wire_pair)
        value = convert(JSON.parse(wire_pair.data))
        wire_pair.status == 1 ? Interpreter::ErrorVal.new(value) : value
      rescue JSON::ParserError
        Interpreter::ErrorVal.internal(
          kind: "syntax_error",
          location: "input",
          operation: "parsing input as JSON",
          input: wire_pair.data,
          message: "input is not valid JSON"
        )
      end

      private

      def convert(ruby_value)
        case ruby_value
        when nil then NULL
        when Array then ruby_value.map { |item| convert(item) }
        when Hash then ruby_value.transform_values { |value| convert(value) }
        else ruby_value
        end
      end
    end
  end
end
