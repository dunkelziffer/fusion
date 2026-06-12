# frozen_string_literal: true

# === CLI internals ===
#
# Input: Interpreter runtime value
# Output: [exit_code, JSON]

module Fusion
  module CLI
    module Serializer
      extend self

      # Encode a runtime value per the output mode (see docs/user/reference.md
      # §9.4). Returns [status, text]: status is 0 for a value and 1 for an
      # error; only the unix mode maps it onto stderr and the exit code — the
      # other modes mark the error inside the text itself.
      def encode(runtime_value, mode:)
        status, json = to_json(runtime_value)
        text =
          case mode
          when :unix then json
          when :bang then status.zero? ? json : "!#{json}"
          when :array then "[#{status},#{json}]"
          when :object then status.zero? ? %({"value":#{json}}) : %({"error":#{json}})
          else raise Unreachable, "Unknown output mode #{mode}"
          end
        [status, text]
      end

      # Render a runtime value for interactive display (the REPL): an error
      # shows as !payload, and values without a JSON form render leniently
      # ("<function>", "<Infinity>", …) instead of erroring.
      def render(runtime_value)
        if runtime_value.is_a?(Interpreter::ErrorVal)
          "!#{convert(runtime_value.payload, lenient: true).to_json}"
        else
          convert(runtime_value, lenient: true).to_json
        end
      end

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
