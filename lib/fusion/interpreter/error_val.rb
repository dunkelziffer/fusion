# frozen_string_literal: true

# === Interpreter internals ===
#
# An error value, always carrying a payload (any JSON-like Fusion value).

module Fusion
  class Interpreter
    class ErrorVal
      attr_reader :payload

      def initialize(payload)
        @payload = payload
        @internal = false
      end

      def internal_error?
        @internal
      end

      # Build an interpreter-produced error (as opposed to a user-constructed `!expr`)
      # with a standardized shape.
      def self.internal(kind:, location:, operation:, input:, message: nil)
        error = new(
          "kind" => kind,
          "location" => location,
          "operation" => operation,
          "input" => input,
          **(message ? { "message" => message } : {})
        )

        # Mark as "@internal" to activate lenient serialization.
        error.instance_variable_set(:@internal, true)

        error
      end

      def inspect
        "!#{payload.inspect}"
      end

      def to_s
        inspect
      end
    end
  end
end
