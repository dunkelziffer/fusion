# frozen_string_literal: true

# === Interpreter internals ===
#
# Lazy, memoized value of a top-level unit (a file, or an inline/REPL entry).
# A bare `@` forces the current unit's thunk; re-entering it before it finishes
# is a non-productive data cycle.

module Fusion
  class Interpreter
    class Thunk
      def initialize(location:, input:, &compute)
        @compute = compute
        @location = location
        @input = input
        @state = :unforced # :unforced | :forcing | :done
        @value = nil
      end

      def force
        case @state
        when :done then @value
        when :forcing
          # We are already computing this unit and were asked for it again
          # without any intervening function boundary => non-productive data cycle.
          ErrorVal.internal(
            kind: "reference_error",
            location: @location,
            operation: "forcing a reference",
            input: @input,
            message: "non-productive data cycle"
          )
        else
          @state = :forcing
          @value = @compute.call
          @state = :done
          @value
        end
      end
    end
  end
end
