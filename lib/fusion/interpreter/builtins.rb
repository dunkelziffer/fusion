# frozen_string_literal: true

# === Interpreter internals ===

module Fusion
  class Interpreter
    module Builtins
      def self.install(table, interp)
        define = ->(name, fn) { table[name] = NativeFunc.new(name, fn) }

        isnum = ->(x) { x.is_a?(Numeric) && !(x == true || x == false) }
        is_pair = ->(v) { v.is_a?(Array) && v.length == 2 }

        # Validate a numeric pair. `argument_error` means "wrong number" (not a
        # pair); `type_error` means a type mismatch (a pair, but not of numbers).
        # Returns [a, b] on success or an ErrorVal.
        num_pair = lambda do |name, v|
          next ErrorVal.internal(kind: "argument_error", location: "builtin #{name}", operation: name, input: v, message: "expected a pair") unless is_pair.call(v)
          a, b = v
          next ErrorVal.internal(kind: "type_error", location: "builtin #{name}", operation: name, input: v, message: "expected numbers") unless isnum.call(a) && isnum.call(b)
          [a, b]
        end

        # --- arithmetic on a pair [a, b] (or unary for negate) ---
        define.call("add", lambda do |v|
          p = num_pair.call("add", v); p.is_a?(ErrorVal) ? p : p[0] + p[1]
        end)
        define.call("subtract", lambda do |v|
          p = num_pair.call("subtract", v); p.is_a?(ErrorVal) ? p : p[0] - p[1]
        end)
        define.call("multiply", lambda do |v|
          p = num_pair.call("multiply", v); p.is_a?(ErrorVal) ? p : p[0] * p[1]
        end)
        define.call("divide", lambda do |v|
          p = num_pair.call("divide", v)
          next p if p.is_a?(ErrorVal)
          a, b = p
          next ErrorVal.internal(kind: "math_error", location: "builtin divide", operation: "divide", input: v, message: "division by zero") if b == 0
          if a.is_a?(Integer) && b.is_a?(Integer) && (a % b == 0) then a / b
          else a.to_f / b end
        end)
        define.call("mod", lambda do |v|
          p = num_pair.call("mod", v)
          next p if p.is_a?(ErrorVal)
          a, b = p
          next ErrorVal.internal(kind: "math_error", location: "builtin mod", operation: "mod", input: v, message: "modulo by zero") if b == 0
          a % b
        end)
        define.call("negate", lambda do |v|
          isnum.call(v) ? -v : ErrorVal.internal(kind: "type_error", location: "builtin negate", operation: "negate", input: v, message: "expected a number")
        end)
        define.call("floor", lambda do |v|
          next ErrorVal.internal(kind: "type_error", location: "builtin floor", operation: "floor", input: v, message: "expected a number") unless isnum.call(v)
          next ErrorVal.internal(kind: "math_error", location: "builtin floor", operation: "floor", input: v, message: "not a finite number") if v.is_a?(Float) && !v.finite?
          v.floor
        end)

        # --- comparison ---
        define.call("equals", lambda do |v|
          next ErrorVal.internal(kind: "argument_error", location: "builtin equals", operation: "equals", input: v, message: "expected a pair") unless is_pair.call(v)
          interp.deep_equal?(v[0], v[1])
        end)
        define.call("lessThan", lambda do |v|
          next ErrorVal.internal(kind: "argument_error", location: "builtin lessThan", operation: "lessThan", input: v, message: "expected a pair") unless is_pair.call(v)
          a, b = v
          if isnum.call(a) && isnum.call(b) then a < b
          elsif a.is_a?(String) && b.is_a?(String) then a < b
          else ErrorVal.internal(kind: "type_error", location: "builtin lessThan", operation: "lessThan", input: v, message: "expected two numbers or two strings") end
        end)

        # --- boolean ---
        bool_pair = lambda do |name, v|
          next ErrorVal.internal(kind: "argument_error", location: "builtin #{name}", operation: name, input: v, message: "expected a pair") unless is_pair.call(v)
          next ErrorVal.internal(kind: "type_error", location: "builtin #{name}", operation: name, input: v, message: "expected booleans") unless v.all? { |x| x == true || x == false }
          v
        end
        define.call("and", lambda do |v|
          p = bool_pair.call("and", v); p.is_a?(ErrorVal) ? p : (p[0] && p[1])
        end)
        define.call("or", lambda do |v|
          p = bool_pair.call("or", v); p.is_a?(ErrorVal) ? p : (p[0] || p[1])
        end)
        define.call("not", lambda do |v|
          (v == true || v == false) ? !v : ErrorVal.internal(kind: "type_error", location: "builtin not", operation: "not", input: v, message: "expected a boolean")
        end)

        # --- strings / structure bridges ---
        define.call("length", lambda do |v|
          case v
          when String, Array, Hash then v.length
          else ErrorVal.internal(kind: "type_error", location: "builtin length", operation: "length", input: v, message: "expected a string, array, or object") end
        end)
        define.call("concat", lambda do |v|
          next ErrorVal.internal(kind: "argument_error", location: "builtin concat", operation: "concat", input: v, message: "expected a pair") unless is_pair.call(v)
          next ErrorVal.internal(kind: "type_error", location: "builtin concat", operation: "concat", input: v, message: "expected strings") unless v.all? { |x| x.is_a?(String) }
          v[0] + v[1]
        end)
        define.call("chars", lambda do |v|
          v.is_a?(String) ? v.chars : ErrorVal.internal(kind: "type_error", location: "builtin chars", operation: "chars", input: v, message: "expected a string")
        end)
        define.call("join", lambda do |v|
          next ErrorVal.internal(kind: "argument_error", location: "builtin join", operation: "join", input: v, message: "expected a pair") unless is_pair.call(v)
          arr, sep = v
          unless arr.is_a?(Array) && sep.is_a?(String) && arr.all? { |x| x.is_a?(String) }
            next ErrorVal.internal(kind: "type_error", location: "builtin join", operation: "join", input: v, message: "expected [array-of-strings, separator-string]")
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
          else ErrorVal.internal(kind: "conversion_error", location: "builtin toString", operation: "toString", input: v, message: "cannot stringify this value type")
          end
        end)
        define.call("parseNumber", lambda do |v|
          next ErrorVal.internal(kind: "type_error", location: "builtin parseNumber", operation: "parseNumber", input: v, message: "expected a string") unless v.is_a?(String)
          if v =~ /\A-?\d+\z/ then v.to_i
          elsif v =~ /\A-?\d+(\.\d+)?([eE][+-]?\d+)?\z/ then v.to_f
          else ErrorVal.internal(kind: "conversion_error", location: "builtin parseNumber", operation: "parseNumber", input: v, message: "not a numeric string")
          end
        end)

        # --- object key enumeration (Tier 0: patterns can't enumerate unknown keys) ---
        define.call("keys", lambda do |v|
          v.is_a?(Hash) ? v.keys : ErrorVal.internal(kind: "type_error", location: "builtin keys", operation: "keys", input: v, message: "expected an object")
        end)
        define.call("values", lambda do |v|
          v.is_a?(Hash) ? v.values : ErrorVal.internal(kind: "type_error", location: "builtin values", operation: "values", input: v, message: "expected an object")
        end)

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
