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

      # `operation`/`input`/`site` describe the *reference* forcing this thunk: the
      # `@`-reference's own source text (`@foo`, `@../p`, `@@`, `@`, or `@load`),
      # `null` (or the `@load` argument), and the referring code's `{origin:, file:}`.
      # They are NOT passed to `@compute`: a thunk computes the unit's value, which
      # is the same for every reference, so it is memoized once. The arguments only
      # matter when the *reference itself* fails — they build the cycle error, and
      # they complete a cached read failure for this reference (see #with_reference).
      # They default to the top-level program load, which has no enclosing reference.
      def force(operation: "loading code", input: NULL, site: { origin: "code", file: nil })
        if @state == :forcing
          # Re-entered while still computing => non-productive data cycle. Built
          # fresh from this reference; cycles are detected here, never memoized.
          return ErrorVal.from_runtime(
            kind: "reference_error", **site, operation: operation, input: input, message: "non-productive data cycle"
          )
        end

        if @state == :unforced
          @state = :forcing
          @value = @compute.call
          @state = :done
        end

        # A read failure is cached once but must report whichever reference forced
        # it, so complete a fresh copy for this one. A value — or any other error
        # (parse/eval) — is already final and returned as memoized.
        @value.is_a?(ErrorVal) && @value.deferred? ? @value.with_reference(operation: operation, input: input, site: site) : @value
      end
    end
  end
end
