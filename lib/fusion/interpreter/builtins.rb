# frozen_string_literal: true

# === Interpreter internals ===

module Fusion
  class Interpreter
    module Builtins
      def self.install(table, interp)
        # Standardized error constructors for a builtin context. `argument_error`
        # means "wrong number" (the input is not the pair/shape the operation
        # needs); `type_error` means "expected X" / a type mismatch.
        type_err = ->(name, input, msg) {
          Errors.make(kind: "type_error", location: "builtin #{name}", operation: name, input: input, message: msg)
        }
        arg_err = ->(name, input, msg) {
          Errors.make(kind: "argument_error", location: "builtin #{name}", operation: name, input: input, message: msg)
        }
        math_err = ->(name, input, msg) {
          Errors.make(kind: "math_error", location: "builtin #{name}", operation: name, input: input, message: msg)
        }
        conv_err = ->(name, input, msg) {
          Errors.make(kind: "conversion_error", location: "builtin #{name}", operation: name, input: input, message: msg)
        }
        define = ->(name, fn) { table[name] = NativeFunc.new(name, fn) }

        isnum = ->(x) { x.is_a?(Numeric) && !(x == true || x == false) }
        is_pair = ->(v) { v.is_a?(Array) && v.length == 2 }

        # Validate a numeric pair: argument_error if not a pair, type_error if the
        # elements aren't both numbers, else [a, b].
        num_pair = lambda do |name, v|
          next arg_err.call(name, v, "expected a pair") unless is_pair.call(v)
          a, b = v
          next type_err.call(name, v, "expected numbers") unless isnum.call(a) && isnum.call(b)
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
          next math_err.call("divide", v, "division by zero") if b == 0
          if a.is_a?(Integer) && b.is_a?(Integer) && (a % b == 0) then a / b
          else a.to_f / b end
        end)
        define.call("mod", lambda do |v|
          p = num_pair.call("mod", v)
          next p if p.is_a?(ErrorVal)
          a, b = p
          next math_err.call("mod", v, "modulo by zero") if b == 0
          a % b
        end)
        define.call("negate", lambda do |v|
          isnum.call(v) ? -v : type_err.call("negate", v, "expected a number")
        end)
        define.call("floor", lambda do |v|
          next type_err.call("floor", v, "expected a number") unless isnum.call(v)
          next math_err.call("floor", v, "not a finite number") if v.is_a?(Float) && !v.finite?
          v.floor
        end)

        # --- comparison ---
        define.call("equals", lambda do |v|
          next arg_err.call("equals", v, "expected a pair") unless is_pair.call(v)
          interp.deep_equal?(v[0], v[1])
        end)
        define.call("lessThan", lambda do |v|
          next arg_err.call("lessThan", v, "expected a pair") unless is_pair.call(v)
          a, b = v
          if isnum.call(a) && isnum.call(b) then a < b
          elsif a.is_a?(String) && b.is_a?(String) then a < b
          else type_err.call("lessThan", v, "expected two numbers or two strings") end
        end)

        # --- boolean ---
        bool_pair = lambda do |name, v|
          next arg_err.call(name, v, "expected a pair") unless is_pair.call(v)
          next type_err.call(name, v, "expected booleans") unless v.all? { |x| x == true || x == false }
          v
        end
        define.call("and", lambda do |v|
          p = bool_pair.call("and", v); p.is_a?(ErrorVal) ? p : (p[0] && p[1])
        end)
        define.call("or", lambda do |v|
          p = bool_pair.call("or", v); p.is_a?(ErrorVal) ? p : (p[0] || p[1])
        end)
        define.call("not", lambda do |v|
          (v == true || v == false) ? !v : type_err.call("not", v, "expected a boolean")
        end)

        # --- strings / structure bridges ---
        define.call("length", lambda do |v|
          case v
          when String, Array, Hash then v.length
          else type_err.call("length", v, "expected a string, array, or object") end
        end)
        define.call("concat", lambda do |v|
          next arg_err.call("concat", v, "expected a pair") unless is_pair.call(v)
          next type_err.call("concat", v, "expected strings") unless v.all? { |x| x.is_a?(String) }
          v[0] + v[1]
        end)
        define.call("chars", lambda do |v|
          v.is_a?(String) ? v.chars : type_err.call("chars", v, "expected a string")
        end)
        define.call("join", lambda do |v|
          next arg_err.call("join", v, "expected a pair") unless is_pair.call(v)
          arr, sep = v
          unless arr.is_a?(Array) && sep.is_a?(String) && arr.all? { |x| x.is_a?(String) }
            next type_err.call("join", v, "expected [array-of-strings, separator-string]")
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
          else conv_err.call("toString", v, "cannot stringify this value type")
          end
        end)
        define.call("parseNumber", lambda do |v|
          next type_err.call("parseNumber", v, "expected a string") unless v.is_a?(String)
          if v =~ /\A-?\d+\z/ then v.to_i
          elsif v =~ /\A-?\d+(\.\d+)?([eE][+-]?\d+)?\z/ then v.to_f
          else conv_err.call("parseNumber", v, "not a numeric string")
          end
        end)

        # --- object key enumeration (Tier 0: patterns can't enumerate unknown keys) ---
        define.call("keys", lambda do |v|
          v.is_a?(Hash) ? v.keys : type_err.call("keys", v, "expected an object")
        end)
        define.call("values", lambda do |v|
          v.is_a?(Hash) ? v.values : type_err.call("values", v, "expected an object")
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
