# frozen_string_literal: true

# === Interpreter internals ===
#
# An error value, always carrying a payload (any JSON-like Fusion value).

module Fusion
  class Interpreter
    class ErrorVal
      attr_reader :payload

      def initialize(payload, runtime: false, deferred: false)
        @payload = payload
        @runtime = runtime
        @deferred = deferred
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

      # Was this error runtime-produced (as opposed to user-constructed via `!expr`)?
      # Runtime errors use lenient serialization (docs/user/reference.md §9.3) and
      # get a call-site `file` stamped.
      def runtime?
        @runtime
      end

      # Whether this is a deferred read failure (see .read_failure): its reference
      # fields are placeholders, awaiting the reference that forces its thunk.
      def deferred?
        @deferred
      end

      # Complete a deferred read failure for the reference that forced its thunk: a
      # copy with the placeholder reference fields (origin/file/operation/input)
      # replaced by this reference's `operation`/`input`/`site`, keeping the
      # failure's kind/message. A copy — the cached deferred error is shared across
      # every reference to the file, so it must never be mutated.
      def with_reference(operation:, input:, site:)
        filled = {}
        @payload.each do |key, value|
          case key
          when "origin"
            filled["origin"] = site[:origin]
            filled["file"] = site[:file] if site[:file] # slots in right after `origin`
          when "operation" then filled["operation"] = operation
          when "input" then filled["input"] = input
          else filled[key] = value
          end
        end
        ErrorVal.new(filled, runtime: true)
      end

      # Build a runtime-produced error with the standardized payload shape
      # documented in docs/user/reference.md §6.5.
      def self.from_runtime(kind:, origin:, operation:, input:, file: nil, expected: nil, message: nil, deferred: false)
        raise Unreachable, "an error with `expected` must not also carry a `message`" if expected && message

        received_error = input.is_a?(ErrorVal)

        payload = { "kind" => kind, "origin" => origin }
        payload["file"] = file if file
        payload["operation"] = operation
        payload["status"] = received_error ? 1 : 0
        payload["input"] = received_error ? input.payload : input
        payload["expected"] = expected if expected
        payload["message"] = message if message

        new(payload, runtime: true, deferred: deferred)
      end

      # A read failure (a missing file, a directory, …) as a reference_error whose
      # reference fields (origin/file/operation/input) are placeholders. The same
      # file is reached by different `@`-references and each must report *itself*,
      # so a Thunk caches this once and completes a copy per force (#with_reference).
      # The placeholders keep it a valid, serializable error until then.
      def self.read_failure(message)
        from_runtime(kind: "reference_error", origin: "code", operation: "loading code", input: NULL, message: message, deferred: true)
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
