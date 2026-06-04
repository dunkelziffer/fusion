# frozen_string_literal: true

# === Interpreter internals ===

module Fusion
  class Interpreter
    module Builtins
      def self.install(table, interp)
        # Helper to construct an informative error from a builtin context.
        err = ->(fn, msg) { ErrorVal.new("#{fn}: #{msg}") }
        define = ->(name, fn) { table[name] = NativeFunc.new(name, fn) }

        # --- arithmetic on a pair [a, b] (or unary for negate) ---
        pair_num = lambda do |v|
          return nil unless v.is_a?(Array) && v.length == 2
          a, b = v
          return nil unless a.is_a?(Numeric) && !(a == true || a == false) &&
                            b.is_a?(Numeric) && !(b == true || b == false)
          [a, b]
        end
        isnum = ->(x) { x.is_a?(Numeric) && !(x == true || x == false) }

        define.call("add", ->(v) {
          p = pair_num.call(v); p ? p[0] + p[1] : err.call("add", "expected a pair of numbers")
        })
        define.call("subtract", ->(v) {
          p = pair_num.call(v); p ? p[0] - p[1] : err.call("subtract", "expected a pair of numbers")
        })
        define.call("multiply", ->(v) {
          p = pair_num.call(v); p ? p[0] * p[1] : err.call("multiply", "expected a pair of numbers")
        })
        define.call("divide", lambda do |v|
          p = pair_num.call(v)
          next err.call("divide", "expected a pair of numbers") unless p
          next err.call("divide", "division by zero") if p[1] == 0
          if p[0].is_a?(Integer) && p[1].is_a?(Integer) && (p[0] % p[1] == 0)
            p[0] / p[1]
          else
            p[0].to_f / p[1]
          end
        end)
        define.call("mod", lambda do |v|
          p = pair_num.call(v)
          next err.call("mod", "expected a pair of numbers") unless p
          next err.call("mod", "modulo by zero") if p[1] == 0
          p[0] % p[1]
        end)
        define.call("negate", ->(v) {
          isnum.call(v) ? -v : err.call("negate", "expected a number")
        })
        define.call("floor", ->(v) {
          isnum.call(v) ? v.floor : err.call("floor", "expected a number")
        })

        # --- comparison ---
        define.call("equals", lambda do |v|
          next err.call("equals", "expected a pair") unless v.is_a?(Array) && v.length == 2
          interp.deep_equal?(v[0], v[1])
        end)
        define.call("lessThan", lambda do |v|
          next err.call("lessThan", "expected two numbers or two strings") unless v.is_a?(Array) && v.length == 2
          a, b = v
          if isnum.call(a) && isnum.call(b) then a < b
          elsif a.is_a?(String) && b.is_a?(String) then a < b
          else err.call("lessThan", "expected two numbers or two strings") end
        end)

        # --- boolean ---
        define.call("and", lambda do |v|
          unless v.is_a?(Array) && v.length == 2 && v.all? { |x| x == true || x == false }
            next err.call("and", "expected a pair of booleans")
          end
          v[0] && v[1]
        end)
        define.call("or", lambda do |v|
          unless v.is_a?(Array) && v.length == 2 && v.all? { |x| x == true || x == false }
            next err.call("or", "expected a pair of booleans")
          end
          v[0] || v[1]
        end)
        define.call("not", ->(v) {
          (v == true || v == false) ? !v : err.call("not", "expected a boolean")
        })

        # --- strings / structure bridges ---
        define.call("length", lambda do |v|
          case v
          when String then v.length
          when Array then v.length
          when Hash then v.length
          else err.call("length", "expected a string, array, or object") end
        end)
        define.call("concat", lambda do |v|
          unless v.is_a?(Array) && v.length == 2 && v.all? { |x| x.is_a?(String) }
            next err.call("concat", "expected a pair of strings")
          end
          v[0] + v[1]
        end)
        define.call("chars", ->(v) {
          v.is_a?(String) ? v.chars : err.call("chars", "expected a string")
        })
        define.call("join", lambda do |v|
          next err.call("join", "expected [array-of-strings, separator-string]") unless v.is_a?(Array) && v.length == 2
          arr, sep = v
          unless arr.is_a?(Array) && sep.is_a?(String) && arr.all? { |x| x.is_a?(String) }
            next err.call("join", "expected [array-of-strings, separator-string]")
          end
          arr.join(sep)
        end)
        define.call("toString", lambda do |v|
          case v
          when String then v
          when Integer, Float then v.to_s
          when true then "true"
          when false then "false"
          when NULL then "null"
          else err.call("toString", "cannot stringify this value type")
          end
        end)
        define.call("parseNumber", lambda do |v|
          next err.call("parseNumber", "expected a string") unless v.is_a?(String)
          if v =~ /\A-?\d+\z/ then v.to_i
          elsif v =~ /\A-?\d+(\.\d+)?([eE][+-]?\d+)?\z/ then v.to_f
          else err.call("parseNumber", "not a numeric string")
          end
        end)

        # --- object key enumeration (Tier 0: patterns can't enumerate unknown keys) ---
        define.call("keys", ->(v) { v.is_a?(Hash) ? v.keys : err.call("keys", "expected an object") })
        define.call("values", ->(v) { v.is_a?(Hash) ? v.values : err.call("values", "expected an object") })

        # --- type predicates (return false on any non-matching value; propagate on error like every other builtin) ---
        define.call("Integer", ->(v) { v.is_a?(Integer) && !(v == true || v == false) })
        define.call("Float", ->(v) { v.is_a?(Float) })
        define.call("Number", ->(v) { isnum.call(v) })
        define.call("String", ->(v) { v.is_a?(String) })
        define.call("Boolean", ->(v) { v == true || v == false })
        define.call("Array", ->(v) { v.is_a?(Array) })
        define.call("Object", ->(v) { v.is_a?(Hash) })
        define.call("Null", ->(v) { v == NULL })
      end
    end
  end
end
