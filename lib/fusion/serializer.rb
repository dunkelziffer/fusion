module Fusion
  # =========================================================================
  # JSON I/O  (minimal, with NULL/ERROR handling)
  # =========================================================================
  module Serializer
    def self.to_json(v)
      case v
      when NULL then "null"
      when true then "true"
      when false then "false"
      when Integer then v.to_s
      when Float then v.to_s
      when String then string_json(v)
      when Array then "[" + v.map { |x| to_json(x) }.join(",") + "]"
      when Hash then "{" + v.map { |k, x| "#{string_json(k.to_s)}:#{to_json(x)}" }.join(",") + "}"
      when Func, NativeFunc then '"<function>"'
      else
        v.equal?(ERROR) ? '"!"' : v.inspect
      end
    end

    def self.string_json(s)
      out = +'"'
      s.each_char do |c|
        out << case c
               when '"' then '\\"'
               when "\\" then "\\\\"
               when "\n" then "\\n"
               when "\t" then "\\t"
               when "\r" then "\\r"
               else c
               end
      end
      out << '"'
      out
    end
  end
end
