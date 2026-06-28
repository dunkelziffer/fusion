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

      # Attach the call-site `file` (slotted after `origin`) to a standardized
      # builtin/stdlib error that lacks one. The interpreter owns `file` — the call
      # site is its knowledge, not the stdlib's — and stamps it at the `apply` that
      # produced the error. A no-op for a plain user error, or one that already
      # carries a `file`, so it's safe on every apply result and stamps only once
      # (at the innermost apply; the call site is constant up a stdlib chain).
      def with_call_site(file)
        return self unless @payload.is_a?(Hash)

        origin = @payload["origin"]
        return self unless (origin == "builtin" || origin == "stdlib") && !@payload.key?("file")

        reordered = {}
        @payload.each do |key, value|
          reordered[key] = value
          reordered["file"] = file if key == "origin"
        end
        @payload = reordered
        self
      end

      # Whether this error was produced by the runtime (vs. a user-constructed
      # `!expr`, or an error arriving as input). Runtime errors always use
      # lenient serialization (see docs/user/reference.md §9.3).
      def runtime?
        @runtime
      end

      # Build a runtime-produced error with the standardized payload shape
      # documented in docs/user/reference.md §6.5.
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

        # Mark as runtime-produced to activate lenient serialization.
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
