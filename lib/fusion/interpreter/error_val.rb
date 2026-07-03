# frozen_string_literal: true

# === Interpreter internals ===
#
# An error value, always carrying a payload (any JSON-like Fusion value).

module Fusion
  class Interpreter
    class ErrorVal
      attr_reader :payload

      def initialize(payload, runtime: false)
        @payload = payload
        @runtime = runtime
      end

      # Attach the call-site `file` to a runtime error. Idempotent.
      def with_call_site(file)
        # Only stamp runtime-produced errors. After this check we are sure that the payload wasn't user-constructed.
        return self unless @runtime
        raise Unreachable, "Unexpected runtime error payload: #{@payload}" unless @payload.is_a?(Hash)
        # Don't double stamp. Idempotency.
        return self if @payload.key?("file")
        # Only stamp certain errors.
        return self unless ["builtin", "stdlib"].include?(@payload["origin"])

        # Insert "file" after "origin"
        reordered = {}
        @payload.each do |key, value|
          reordered[key] = value
          reordered["file"] = file if key == "origin"
        end
        @payload = reordered
        self
      end

      # Return a copy of this runtime error with its `operation` replaced (keeping
      # the field's position). Used by a built-in that delegates to another
      # operation but reports its own `@`-reference (e.g. `@get` over `@OP.get`).
      def with_operation(operation)
        return self unless @runtime && @payload.is_a?(Hash) && @payload.key?("operation")

        copy = @payload.dup
        copy["operation"] = operation
        ErrorVal.new(copy, runtime: @runtime)
      end

      # True if this is a runtime error the operation produced *itself*, freshly,
      # not yet stamped with a call-site `file`. An error bubbling up from within
      # (a nested operation) is already file-stamped, so this is false for it —
      # letting a wrapper re-tag only its own error (see #apply_op_member).
      def own_runtime_error?
        @runtime && @payload.is_a?(Hash) && !@payload.key?("file")
      end

      # Return a copy with `origin` and `operation` replaced (keeping their
      # positions). The caller must ensure this is the operation's own error
      # (#own_runtime_error?).
      def retag(origin:, operation:)
        copy = @payload.dup
        copy["origin"] = origin
        copy["operation"] = operation
        ErrorVal.new(copy, runtime: @runtime)
      end

      # Was this error runtime-produced (as opposed to user-constructed via `!expr`)?
      # Runtime errors use lenient serialization (docs/user/reference.md §9.3) and
      # get a call-site `file` stamped.
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

        new(payload, runtime: true)
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
