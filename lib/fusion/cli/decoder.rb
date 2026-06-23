# frozen_string_literal: true

# === CLI internals ===

require "json"
require_relative "../wire_pair"

module Fusion
  module CLI
    module Decoder
      extend self

      # The acceptable envelope shapes, as Fusion patterns, per input mode.
      ENVELOPE_SHAPES = {
        array: ["[0, _]", "[1, _]"],
        object: ['{"value": _}', '{"error": _}'],
      }.freeze

      # String -> WirePair
      # Doesn't support mode `:unix`
      def decode(text, mode:)
        case mode
        when :bang
          decode_bang(text)
        when :array
          decode_envelope(text, mode) do |raw|
            next unless raw.is_a?(Array) && raw.length == 2 && raw[0].is_a?(Integer)

            # The tag must be exactly the integer 0 or 1 (no 0.0 — Fusion equality is exact).
            [raw[0], raw[1]] if raw[0] == 0 || raw[0] == 1
          end
        when :object
          decode_envelope(text, mode) do |raw|
            next unless raw.is_a?(Hash) && raw.size == 1

            if raw.key?("value") then [0, raw["value"]]
            elsif raw.key?("error") then [1, raw["error"]]
            end
          end
        else
          raise Unreachable, "Unknown input mode #{mode}"
        end
      end

      private

      # bang: a leading "!" marks an error value; its payload is the JSON after
      # the "!". A lone "!" is the error !null, mirroring the language's bare !.
      def decode_bang(text)
        stripped = text.strip
        return WirePair.new(status: 0, data: text) unless stripped.start_with?("!")

        payload = stripped.delete_prefix("!")
        WirePair.new(status: 1, data: payload.strip.empty? ? "null" : payload)
      end

      # array/object: the input is an envelope around the actual value. The block
      # inspects the JSON (raw Ruby, so nulls are nil) and returns [status, inner]
      # or nil for a wrong shape. The inner is re-emitted as JSON text for the
      # pair; invalid JSON falls through to `parse` as a value to fail on, so the
      # syntax_error stays in one place.
      def decode_envelope(text, mode)
        raw = JSON.parse(text)
        status, inner = yield(raw)
        return WirePair.new(status: status, data: JSON.generate(inner)) if status

        WirePair.new(status: 1, data: JSON.generate(
          "kind" => "argument_error",
          "location" => "input",
          "operation" => "decoding input",
          "status" => 0,
          "input" => raw,
          "expected" => ENVELOPE_SHAPES.fetch(mode)
        ))
      rescue JSON::ParserError
        # TODO: BUG ???
        WirePair.new(status: 0, data: text)
      end
    end
  end
end
