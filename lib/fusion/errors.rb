# frozen_string_literal: true

# === Standardized error payloads ===
#
# Every payloaded error the language produces shares one shape:
#
#   { "kind", "location", "operation", "input"[, "message"] }
#
# See docs/lang/design.md §2.9 for the catalog and the meaning of each field.
#   - kind:      one closed set (parse_error, reference_error, type_error,
#                argument_error, binding_error, access_error, math_error,
#                conversion_error, stack_error, serialization_error).
#   - location:  where the failing operation lives — "builtin X", "stdlib X",
#                "code X", "input", "output", or "interpreter". Never the program
#                source as "input"/"output" (those slots are data, not code).
#   - operation: the operation that failed, e.g. "|" or "parsing a guardpat".
#   - input:     the operands the operation received (a runtime value, rendered
#                best-effort by the serializer so reporting never itself fails).
#   - message:   optional human detail, e.g. "expected an object".

require_relative "interpreter/null"
require_relative "interpreter/error_val"

module Fusion
  module Errors
    module_function

    # Build a standardized error value.
    def make(kind:, location:, operation:, input:, message: nil)
      payload = {
        "kind" => kind,
        "location" => location,
        "operation" => operation,
        "input" => input,
      }
      payload["message"] = message if message
      Interpreter::ErrorVal.new(payload)
    end

    # Map a rescued Ruby exception onto a standardized payload. Used by the safety
    # nets that wrap builtin calls, file loading, and the top-level run so that no
    # Ruby backtrace ever reaches stderr — the CLI's only error channel.
    #
    # The two internal-invariant asserts (FusionError "Cannot evaluate node" /
    # "Unknown pattern") are deliberately NOT routed here: reaching them is an
    # interpreter bug, and the caller lets them raise.
    def from_exception(err, location:, operation:, input:)
      case err
      when SystemStackError
        make(kind: "stack_error", location: "interpreter", operation: operation,
             input: input, message: "recursion too deep")
      when FloatDomainError
        make(kind: "math_error", location: location, operation: operation,
             input: input, message: "not a finite number")
      when ZeroDivisionError
        make(kind: "math_error", location: location, operation: operation,
             input: input, message: "division by zero")
      when SystemCallError # Errno::* — file-system access failures
        make(kind: "reference_error", location: location, operation: operation,
             input: input, message: err.message)
      else
        make(kind: "type_error", location: location, operation: operation,
             input: input, message: err.message)
      end
    end
  end
end
