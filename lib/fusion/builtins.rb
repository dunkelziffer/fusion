module Fusion
  # =========================================================================
  # BUILT-INS  (Tier 0 primitives; everything else is written in Fusion)
  # =========================================================================
  module Builtins
    def self.install(env, interp)
      # We model built-ins as Ruby procs wrapped in NativeFunc so `apply` can call them.
      define = ->(name, fn) { env.define(name, NativeFunc.new(name, fn)) }

      bad = ERROR

      # --- arithmetic on a pair [a, b] (or unary for negate) ---
      pair_num = lambda do |v|
        return nil unless v.is_a?(Array) && v.length == 2
        a, b = v
        return nil unless a.is_a?(Numeric) && b.is_a?(Numeric)
        [a, b]
      end

      define.call("add", ->(v) { (p = pair_num.call(v)) ? p[0] + p[1] : bad })
      define.call("subtract", ->(v) { (p = pair_num.call(v)) ? p[0] - p[1] : bad })
      define.call("multiply", ->(v) { (p = pair_num.call(v)) ? p[0] * p[1] : bad })
      define.call("divide", lambda do |v|
        p = pair_num.call(v)
        next bad unless p
        next bad if p[1] == 0
        if p[0].is_a?(Integer) && p[1].is_a?(Integer) && (p[0] % p[1] == 0)
          p[0] / p[1]
        else
          p[0].to_f / p[1]
        end
      end)
      define.call("mod", lambda do |v|
        p = pair_num.call(v)
        next bad unless p
        next bad if p[1] == 0
        p[0] % p[1]
      end)
      define.call("negate", ->(v) { v.is_a?(Numeric) ? -v : bad })
      define.call("floor", ->(v) { v.is_a?(Numeric) ? v.floor : bad })

      # --- comparison ---
      define.call("equals", lambda do |v|
        next bad unless v.is_a?(Array) && v.length == 2
        interp.deep_equal?(v[0], v[1])
      end)
      define.call("lessThan", lambda do |v|
        next bad unless v.is_a?(Array) && v.length == 2
        a, b = v
        if a.is_a?(Numeric) && b.is_a?(Numeric) then a < b
        elsif a.is_a?(String) && b.is_a?(String) then a < b
        else bad end
      end)

      # --- boolean ---
      define.call("and", lambda do |v|
        next bad unless v.is_a?(Array) && v.length == 2 && v.all? { |x| x == true || x == false }
        v[0] && v[1]
      end)
      define.call("or", lambda do |v|
        next bad unless v.is_a?(Array) && v.length == 2 && v.all? { |x| x == true || x == false }
        v[0] || v[1]
      end)
      define.call("not", ->(v) { (v == true || v == false) ? !v : bad })

      # --- strings / structure bridges ---
      define.call("length", lambda do |v|
        case v
        when String then v.length
        when Array then v.length
        when Hash then v.length
        else bad end
      end)
      define.call("concat", lambda do |v|
        next bad unless v.is_a?(Array) && v.length == 2 && v.all? { |x| x.is_a?(String) }
        v[0] + v[1]
      end)
      define.call("chars", ->(v) { v.is_a?(String) ? v.chars : bad })
      define.call("join", lambda do |v|
        next bad unless v.is_a?(Array) && v.length == 2
        arr, sep = v
        next bad unless arr.is_a?(Array) && sep.is_a?(String) && arr.all? { |x| x.is_a?(String) }
        arr.join(sep)
      end)
      define.call("toString", lambda do |v|
        case v
        when String then v
        when Integer, Float then v.to_s
        when true then "true"
        when false then "false"
        when NULL then "null"
        else (v.equal?(ERROR) ? bad : Serializer.to_json(v)) end
      end)
      define.call("parseNumber", lambda do |v|
        next bad unless v.is_a?(String)
        if v =~ /\A-?\d+\z/ then v.to_i
        elsif v =~ /\A-?\d+(\.\d+)?([eE][+-]?\d+)?\z/ then v.to_f
        else bad end
      end)

      # --- object key enumeration (Tier 0: patterns can't enumerate unknown keys) ---
      define.call("keys", ->(v) { v.is_a?(Hash) ? v.keys : bad })
      define.call("values", ->(v) { v.is_a?(Hash) ? v.values : bad })

      # --- type predicates (return false, never !, on any input) ---
      define.call("Integer", ->(v) { v.is_a?(Integer) })
      define.call("Float", ->(v) { v.is_a?(Float) })
      define.call("Number", ->(v) { v.is_a?(Numeric) })
      define.call("String", ->(v) { v.is_a?(String) })
      define.call("Boolean", ->(v) { v == true || v == false })
      define.call("Array", ->(v) { v.is_a?(Array) })
      define.call("Object", ->(v) { v.is_a?(Hash) })
      define.call("Null", ->(v) { v == NULL })
    end
  end
end
