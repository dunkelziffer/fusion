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
        when Interpreter::Func, Interpreter::NativeFunc
          '"<function>"' # TODO: Functions can't be serialized, BUG!!!
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
