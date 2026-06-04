# frozen_string_literal: true

# === CLI internals ===
#
# Input: Interpreter runtime value
# Output: JSON

module Fusion
  module CLI
    module Serializer
      extend self

      def to_json(runtime_value)
        case runtime_value
        when Interpreter::Func, Interpreter::NativeFunc then '"<function>"' # TODO: Functions can't be serialized, BUG!!!
        when Interpreter::ErrorVal
          # Errors render as `!<payload-json>`. This form is NOT valid JSON; the CLI
          # prints the payload (as JSON) to stderr and nothing to stdout on error.
          "!" + convert(runtime_value.payload).to_json # TODO: "!" shouldn't get printed, BUG!!! Serializer should never receive an ErrorVal, it should be handled at a higher level.
        else
          convert(runtime_value).to_json
        end
      end

      private

      # returns a JSON-like Ruby value
      def convert(runtime_value)
        case runtime_value
        when Interpreter::NULL then nil
        when Array then runtime_value.map { |item| convert(item) }
        when Hash then runtime_value.transform_values { |value| convert(value) }
        else runtime_value
        end
      end
    end
  end
end
