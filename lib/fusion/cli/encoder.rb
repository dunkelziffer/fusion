# frozen_string_literal: true

# === CLI internals ===

module Fusion
  module CLI
    module Encoder
      extend self

      # WirePair -> String
      # Doesn't support mode `:unix`
      def encode(wire_pair, mode:)
        case mode
        when :bang
          bang = wire_pair.status == 0 ? "" : "!"
          "#{bang}#{wire_pair.data}"
        when :array
          "[#{wire_pair.status},#{wire_pair.data}]"
        when :object
          key = wire_pair.status == 0 ? "value" : "error"
          "{\"#{key}\":#{wire_pair.data}}"
        else
          raise Unreachable, "Unknown output mode #{mode}"
        end
      end
    end
  end
end
