# frozen_string_literal: true

# === CLI internals ===
#
# Input: Interpreter runtime value
# Output: [exit_code, JSON]

module Fusion
  module CLI
    module Serializer
      extend self

      # Serialize a runtime value into [exit_code, json] per the CLI/serialization
      # contract in docs/user/reference.md §9.3.
      def to_json(runtime_value)
        message = catch(:unserializable) do
          if runtime_value.is_a?(Interpreter::ErrorVal)
            return [1, convert(runtime_value.payload, lenient: runtime_value.internal_error?).to_json]
          else
            return [0, convert(runtime_value).to_json]
          end
        end

        internal_error = Interpreter::ErrorVal.internal(
          kind: "serialization_error",
          location: "output",
          operation: "serializing result",
          input: runtime_value,
          message: message
        )

        to_json(internal_error)
      end

      private

      # Use "lenient: true" only for best-effort serialization of internal errors.
      def convert(runtime_value, lenient: false)
        case runtime_value
        when NULL
          nil
        when Float
          return runtime_value if runtime_value.finite?
          throw(:unserializable, "cannot serialize a non-finite number") unless lenient

          "<#{runtime_value}>" # "<Infinity>" / "<-Infinity>" / "<NaN>"
        when Array
          runtime_value.map { |item| convert(item, lenient:) }
        when Hash
          runtime_value.transform_values { |value| convert(value, lenient:) }
        when Interpreter::Func, Interpreter::NativeFunc
          throw(:unserializable, "cannot serialize a function") unless lenient

          "<function>"
        when true, false, String, Numeric
          runtime_value
        when Interpreter::ErrorVal
          if lenient
            "!#{convert(runtime_value.payload, lenient:).to_json}"
          else
            raise Unreachable, "ErrorVal should have been handled at the top level of convert"
          end
        else
          raise Unreachable, "Unhandled type in convert: #{runtime_value.class}"
        end
      end
    end
  end
end
