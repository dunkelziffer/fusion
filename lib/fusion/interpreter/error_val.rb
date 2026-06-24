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
        @runtime = false
      end

      # Whether this error was produced by the runtime (vs. a user-constructed
      # `!expr`, or an error arriving as input). Governs serialization — see
      # docs/user/reference.md §9.3.
      def runtime?
        @runtime
      end

      # Build a runtime-produced error with the standardized payload shape
      # documented in docs/user/reference.md §6.5. `origin` is one of the six
      # fixed values; `file` carries the source basename when there is one.
      #
      # `status`/`input` are derived here: if the operation received an error
      # value, `status` is 1 and `input` is its bare payload (so `input` stays
      # valid JSON); otherwise `status` is 0 and `input` is the value itself
      # (0/1 mirror the wire status codes). `expected` lists acceptable inputs as
      # Fusion patterns and is mutually exclusive with `message`.
      def self.from_runtime(kind:, origin:, operation:, input:, file: nil, expected: nil, message: nil)
        raise Unreachable, "an error with `expected` must not also carry a `message`" if expected && message

        received_error = input.is_a?(ErrorVal)

        payload = { "kind" => kind, "origin" => origin }
        payload["file"] = file if file
        payload["operation"] = operation
        payload["status"] = received_error ? 1 : 0
        payload["input"] = received_error ? input.payload : input
        payload["expected"] = expected if expected
        payload["message"] = message if message

        error = new(payload)

        # Flag as runtime-produced to activate lenient serialization.
        error.instance_variable_set(:@runtime, true)

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
