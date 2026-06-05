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
      end

      # Build a standardized, interpreter-produced error (as opposed to a
      # user-constructed `!expr`). Every such payload shares one shape — see
      # docs/lang/design.md §2.9 for the field meanings and the closed `kind`
      # and `location` sets.
      def self.internal(kind:, location:, operation:, input:, message: nil)
        payload = {
          "kind" => kind,
          "location" => location,
          "operation" => operation,
          "input" => input,
        }
        payload["message"] = message if message
        new(payload)
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
