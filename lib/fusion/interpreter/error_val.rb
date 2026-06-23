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

      # Whether this is an interpreter-produced error (vs. a user-constructed
      # `!expr`). Governs serialization — see docs/user/reference.md §9.3.
      def internal_error?
        @internal
      end

      # Build an interpreter-produced error with the standardized payload shape
      # documented in docs/user/reference.md §6.5. `location` is one of the six
      # fixed values; `file` carries the source basename when there is one.
      #
      # `status`/`input` are derived here: if the operation received an error
      # value, `status` is "error" and `input` is its bare payload (so `input`
      # stays valid JSON); otherwise `status` is "value" and `input` is the value
      # itself. `expected` lists acceptable inputs as Fusion patterns and is
      # mutually exclusive with `message`.
      def self.internal(kind:, location:, operation:, input:, file: nil, expected: nil, message: nil)
        raise Unreachable, "an error with `expected` must not also carry a `message`" if expected && message

        received_error = input.is_a?(ErrorVal)

        payload = { "kind" => kind, "location" => location }
        payload["file"] = file if file
        payload["operation"] = operation
        payload["status"] = received_error ? "error" : "value"
        payload["input"] = received_error ? input.payload : input
        payload["expected"] = expected if expected
        payload["message"] = message if message

        error = new(payload)

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
