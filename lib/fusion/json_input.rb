module Fusion
  # =========================================================================
  # JSON I/O  (minimal, with NULL/ERROR handling)
  # =========================================================================
  module JsonInput
    # Parse JSON text into Fusion values (null -> NULL).
    def self.parse(text)
      require "json"
      raw = JSON.parse(text)
      convert(raw)
    rescue JSON::ParserError
      ERROR
    end

    def self.convert(x)
      case x
      when nil then NULL
      when Array then x.map { |e| convert(e) }
      when Hash then x.each_with_object({}) { |(k, v), h| h[k] = convert(v) }
      else x
      end
    end
  end
end

