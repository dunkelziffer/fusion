# frozen_string_literal: true

# === Value ===
#
# The combination of status code and value (JSON string)

require_relative "typed_data"

module Fusion
  WirePair = TypedData.define(status: ->(v) { Integer === v && [0, 1].include?(v) }, data: String)
end
