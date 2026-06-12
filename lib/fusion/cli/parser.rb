# frozen_string_literal: true

# === CLI internals ===
#
# Input: JSON text (plus the input mode's error marking)
# Output: Interpreter runtime value
#
# A failure to decode is not fatal: it becomes an internal error value at
# location "input" that flows through the program like any other error input,
# so a program can catch it.

require "json"

module Fusion
  module CLI
    module Parser
      extend self

      # Decode one input per the input mode (see docs/user/reference.md §9.4).
      # Returns a runtime value; an error input decodes to an ErrorVal.
      def decode(text, mode:)
        case mode
        when :unix
          parse(text)
        when :bang
          decode_bang(text)
        when :array
          decode_envelope(parse(text), mode) do |decoded|
            # The tag must be exactly the integer 0 or 1 (no 0.0 — Fusion equality is exact).
            next unless decoded.is_a?(Array) && decoded.length == 2 && decoded[0].is_a?(Integer)

            case decoded[0]
            when 0 then [:value, decoded[1]]
            when 1 then [:error, decoded[1]]
            end
          end
        when :object
          decode_envelope(parse(text), mode) do |decoded|
            next unless decoded.is_a?(Hash) && decoded.size == 1

            if decoded.key?("value")
              [:value, decoded["value"]]
            elsif decoded.key?("error")
              [:error, decoded["error"]]
            end
          end
        else
          raise Unreachable, "Unknown input mode #{mode}"
        end
      end

      def parse(json)
        ruby_value = JSON.parse(json)
        convert(ruby_value)
      rescue JSON::ParserError
        Interpreter::ErrorVal.internal(
          kind: "syntax_error",
          location: "input",
          operation: "parsing input as JSON",
          input: json,
          message: "input is not valid JSON"
        )
      end

      private

      # bang: a leading "!" marks an error value; its payload is the JSON after
      # the "!". A lone "!" is the error !null, mirroring the language's bare !.
      def decode_bang(text)
        stripped = text.strip
        return parse(text) unless stripped.start_with?("!")

        payload_text = stripped.delete_prefix("!")
        return Interpreter::ErrorVal.new(NULL) if payload_text.strip.empty?

        payload = parse(payload_text)
        # A payload that failed to parse is already an error; never nest errors.
        payload.is_a?(Interpreter::ErrorVal) ? payload : Interpreter::ErrorVal.new(payload)
      end

      ENVELOPE_SHAPES = {
        array: "[0, _] or [1, _]",
        object: '{"value": _} or {"error": _}',
      }.freeze

      # array/object: the input is an envelope around the actual value. The block
      # inspects the decoded JSON and returns [:value, v] / [:error, payload], or
      # nil if the envelope shape is wrong.
      def decode_envelope(decoded, mode)
        return decoded if decoded.is_a?(Interpreter::ErrorVal) # not valid JSON to begin with

        tag, inner = yield(decoded)
        case tag
        when :value then inner
        when :error then Interpreter::ErrorVal.new(inner)
        else
          Interpreter::ErrorVal.internal(
            kind: "argument_error",
            location: "input",
            operation: "decoding input",
            input: decoded,
            message: "expected #{ENVELOPE_SHAPES.fetch(mode)}"
          )
        end
      end

      # returns a runtime value
      def convert(ruby_value)
        case ruby_value
        when nil then NULL
        when Array then ruby_value.map { |item| convert(item) }
        when Hash then ruby_value.transform_values { |value| convert(value) }
        else ruby_value
        end
      end
    end
  end
end
