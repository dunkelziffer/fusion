# frozen_string_literal: true

# === CLI internals ===
#
# Input: Interpreter runtime value
# Output: JSON

module Fusion
  module CLI
    module Serializer
      extend self

      # Render a runtime value as JSON. Never raises: functions become
      # "<function>" and non-finite floats become strings, so this is safe to use
      # for error payloads (whose "input" field may hold such values).
      def to_json(runtime_value)
        convert(runtime_value).to_json
      end

      # Whether a value can be faithfully emitted as a program result. A function
      # (anywhere in the value) cannot be serialized to JSON; the CLI reports that
      # as a serialization_error rather than emitting a "<function>" placeholder.
      def serializable?(runtime_value)
        case runtime_value
        when Interpreter::Func, Interpreter::NativeFunc then false
        when Array then runtime_value.all? { |item| serializable?(item) }
        when Hash then runtime_value.values.all? { |value| serializable?(value) }
        else true
        end
      end

      private

      # returns a JSON-like Ruby value
      def convert(runtime_value)
        case runtime_value
        when Interpreter::NULL then nil
        when Interpreter::Func, Interpreter::NativeFunc then "<function>"
        when Float
          # Infinity / NaN are not valid JSON; render best-effort as a string.
          runtime_value.finite? ? runtime_value : runtime_value.to_s
        when Array then runtime_value.map { |item| convert(item) }
        when Hash then runtime_value.transform_values { |value| convert(value) }
        else runtime_value
        end
      end
    end
  end
end
