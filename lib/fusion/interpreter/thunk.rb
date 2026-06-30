# frozen_string_literal: true

# === Interpreter internals ===
#
# Lazy, memoized value of a top-level unit (a file, or an inline/REPL entry).

module Fusion
  class Interpreter
    class Thunk
      # We use a custom Ruby error to transmit read failures between `Interpreter.evaluate_file`
      # (which runs in the @compute block) and the Thunk to enforce their connection.
      # If `Interpreter.evaluate_file` were to be used outside of a Thunk, the Ruby error would
      # bubble and trigger an `internal_error` later on.
      class ReadFailure < StandardError; end

      def initialize(&compute)
        @compute = compute
        @state = :unforced # :unforced | :forcing | :done
        @value = nil # memoized result: runtime value/error | ReadFailure
      end

      # `operation`/`input`/`site` describe the @-reference forcing this thunk.
      # They are NOT passed to `@compute`, because they differ when evaluating the same
      # Thunk for different @-references. They MUST NOT become part or the memoized value.
      def force(operation: "loading code", input: NULL, site: { origin: "code", file: nil })
        result = case @state
        when :done
          @value
        when :forcing
          # Re-entering while still computing results in a non-productive data cycle. Not memoized.
          ErrorVal.from_runtime(kind: "reference_error", **site, operation: operation, input: input, message: "non-productive data cycle")
        when :unforced
          @state = :forcing
          begin
            @value = @compute.call
          rescue ReadFailure => failure
            # Memoize the Ruby error itself. Turn it into a Fusion runtime error below.
            @value = failure
          end
          @state = :done
          @value
        end

        case result
        when ReadFailure
          ErrorVal.from_runtime(kind: "reference_error", **site, operation: operation, input: input, message: result.message)
        else
          result
        end
      end
    end
  end
end
