# frozen_string_literal: true

# === Interpreter internals ===
#
# Lazy, memoized value of a top-level unit (a file, or an inline/REPL entry).

module Fusion
  class Interpreter
    class Thunk
      def initialize(&compute)
        @compute = compute
        @state = :unforced # :unforced | :forcing | :done
        @value = nil
      end

      # `operation`/`input`/`site` describe the *reference* being forced — the
      # `@`-reference's own source text (`@foo`, `@../p`, `@@`, `@`, or `@load`),
      # `null` (or the `@load` argument), and the referring code's `{origin:, file:}`.
      # They build the cycle error when this thunk is already being forced (a
      # non-productive data cycle), and reach the compute block for a read failure.
      # They default to the top-level program load, which has no enclosing reference.
      def force(operation: "reading file", input: NULL, site: { origin: "code", file: nil })
        case @state
        when :done then @value
        when :forcing
          # We are already evaluating this unit and were asked for it again
          # without any intervening function boundary => non-productive data cycle.
          ErrorVal.from_runtime(
            kind: "reference_error",
            **site,
            operation: operation,
            input: input,
            message: "non-productive data cycle"
          )
        else
          @state = :forcing
          @value = @compute.call(operation, input, site)
          @state = :done
          @value
        end
      end
    end
  end
end
