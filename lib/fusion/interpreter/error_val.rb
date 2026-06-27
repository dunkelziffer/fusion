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
        @call_site_resolved = false
      end

      # Attach the call-site `file` (where this error's `operation` was invoked)
      # the first time the error passes back out through `apply`. Only the
      # standardized builtin/stdlib errors take a `file`; it slots in right after
      # `origin`. The once-only flag keeps it idempotent and — crucially — stops an
      # inner error from being re-attributed to an outer caller as it bubbles
      # through a function (e.g. an `f`-error must not be relabelled to `@map`'s
      # call site). A built-in error born at a stdlib call site is thus resolved
      # there with no `file`, and stays that way.
      def resolve_call_site(file)
        return self if @call_site_resolved

        origin = @payload.is_a?(Hash) ? @payload["origin"] : nil
        return self unless origin == "builtin" || origin == "stdlib"

        @call_site_resolved = true
        return self unless file && !@payload.key?("file")

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
