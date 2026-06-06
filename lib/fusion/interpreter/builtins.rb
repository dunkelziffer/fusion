# frozen_string_literal: true

# === Interpreter internals ===

module Fusion
  class Interpreter
    module Builtins
      extend self

      def install(table, interp)
        @interp = interp
        define = ->(name, fn) { table[name] = NativeFunc.new(name, fn) }

        # operations on a pair [a, b] (or a single value)
        define.call("add", method(:add))
        define.call("subtract", method(:subtract))
        define.call("multiply", method(:multiply))
        define.call("divide", method(:divide))
        define.call("mod", method(:mod))
        define.call("negate", method(:negate))
        define.call("floor", method(:floor))
        define.call("equals", method(:equals))
        define.call("lessThan", method(:less_than))
        define.call("and", method(:and_))
        define.call("or", method(:or_))
        define.call("not", method(:not_))
        define.call("length", method(:length))
        define.call("concat", method(:concat))
        define.call("chars", method(:chars))
        define.call("join", method(:join))
        define.call("toString", method(:to_string))
        define.call("parseNumber", method(:parse_number))
        define.call("keys", method(:keys))
        define.call("values", method(:values))
        define.call("get", method(:get))
        define.call("set", method(:set))
        define.call("toObject", method(:to_object))

        # type predicates: return false on any non-matching value, never an error
        define.call("Integer", method(:integer?))
        define.call("Float", method(:float?))
        define.call("Number", method(:numeric?))
        define.call("String", method(:string?))
        define.call("Boolean", method(:boolean?))
        define.call("Array", method(:array?))
        define.call("Object", method(:object?))
        define.call("Null", method(:null?))
        define.call("Function", method(:function?))
        define.call("NonFinite", method(:non_finite?))
      end

      # --- arithmetic ---

      def add(v)
        return v if v.is_a?(ErrorVal)
        return error("argument_error", "add", v, "expected [_, _]") unless pair?(v)
        return error("type_error", "add", v, "expected numbers") unless numeric?(v[0])
        return error("type_error", "add", v, "expected numbers") unless numeric?(v[1])

        v[0] + v[1]
      end

      def subtract(v)
        return v if v.is_a?(ErrorVal)
        return error("argument_error", "subtract", v, "expected [_, _]") unless pair?(v)
        return error("type_error", "subtract", v, "expected numbers") unless numeric?(v[0])
        return error("type_error", "subtract", v, "expected numbers") unless numeric?(v[1])

        v[0] - v[1]
      end

      def multiply(v)
        return v if v.is_a?(ErrorVal)
        return error("argument_error", "multiply", v, "expected [_, _]") unless pair?(v)
        return error("type_error", "multiply", v, "expected numbers") unless numeric?(v[0])
        return error("type_error", "multiply", v, "expected numbers") unless numeric?(v[1])

        v[0] * v[1]
      end

      def divide(v)
        return v if v.is_a?(ErrorVal)
        return error("argument_error", "divide", v, "expected [_, _]") unless pair?(v)
        return error("type_error", "divide", v, "expected numbers") unless numeric?(v[0])
        return error("type_error", "divide", v, "expected numbers") unless numeric?(v[1])
        return error("math_error", "divide", v, "division by zero") if v[1] == 0

        a, b = v
        if a.is_a?(Integer) && b.is_a?(Integer) && (a % b).zero?
          a / b
        else
          a.to_f / b
        end
      end

      def mod(v)
        return v if v.is_a?(ErrorVal)
        return error("argument_error", "mod", v, "expected [_, _]") unless pair?(v)
        return error("type_error", "mod", v, "expected numbers") unless numeric?(v[0])
        return error("type_error", "mod", v, "expected numbers") unless numeric?(v[1])
        return error("math_error", "mod", v, "modulo by zero") if v[1] == 0

        v[0] % v[1]
      end

      def negate(v)
        return v if v.is_a?(ErrorVal)
        return error("type_error", "negate", v, "expected a number") unless numeric?(v)

        -v
      end

      def floor(v)
        return v if v.is_a?(ErrorVal)
        return error("type_error", "floor", v, "expected a number") unless numeric?(v)
        return error("math_error", "floor", v, "not a finite number") if non_finite?(v)

        v.floor
      end

      # --- comparison ---

      def equals(v)
        return v if v.is_a?(ErrorVal)
        return error("argument_error", "equals", v, "expected [_, _]") unless pair?(v)

        @interp.deep_equal?(v[0], v[1])
      end

      def less_than(v)
        return v if v.is_a?(ErrorVal)
        return error("argument_error", "lessThan", v, "expected [_, _]") unless pair?(v)

        a, b = v
        if numeric?(a) && numeric?(b)
          a < b
        elsif a.is_a?(String) && b.is_a?(String)
          a < b
        else
          error("type_error", "lessThan", v, "expected two numbers or two strings")
        end
      end

      # --- boolean ---

      def and_(v)
        return v if v.is_a?(ErrorVal)
        return error("argument_error", "and", v, "expected [_, _]") unless pair?(v)
        return error("type_error", "and", v, "expected booleans") unless boolean?(v[0])
        return error("type_error", "and", v, "expected booleans") unless boolean?(v[1])

        v[0] && v[1]
      end

      def or_(v)
        return v if v.is_a?(ErrorVal)
        return error("argument_error", "or", v, "expected [_, _]") unless pair?(v)
        return error("type_error", "or", v, "expected booleans") unless boolean?(v[0])
        return error("type_error", "or", v, "expected booleans") unless boolean?(v[1])

        v[0] || v[1]
      end

      def not_(v)
        return v if v.is_a?(ErrorVal)
        return error("type_error", "not", v, "expected a boolean") unless boolean?(v)

        !v
      end

      # --- strings and structure bridges ---

      def length(v)
        return v if v.is_a?(ErrorVal)
        return error("type_error", "length", v, "expected a string, array, or object") unless v.is_a?(String) || v.is_a?(Array) || v.is_a?(Hash)

        v.length
      end

      def concat(v)
        return v if v.is_a?(ErrorVal)
        return error("argument_error", "concat", v, "expected [_, _]") unless pair?(v)
        return error("type_error", "concat", v, "expected strings") unless v[0].is_a?(String) && v[1].is_a?(String)

        v[0] + v[1]
      end

      def chars(v)
        return v if v.is_a?(ErrorVal)
        return error("type_error", "chars", v, "expected a string") unless v.is_a?(String)

        v.chars
      end

      def join(v)
        return v if v.is_a?(ErrorVal)
        return error("argument_error", "join", v, "expected [_, _]") unless pair?(v)

        array, separator = v
        unless array.is_a?(Array) && separator.is_a?(String) && array.all? { |item| item.is_a?(String) }
          return error("type_error", "join", v, "expected [array-of-strings, separator-string]")
        end

        array.join(separator)
      end

      def to_string(v)
        return v if v.is_a?(ErrorVal)

        case v
        when String then v
        when Integer, Float then v.to_s
        when true then "true"
        when false then "false"
        when NULL then "null"
        else error("conversion_error", "toString", v, "cannot stringify this value type")
        end
      end

      def parse_number(v)
        return v if v.is_a?(ErrorVal)
        return error("type_error", "parseNumber", v, "expected a string") unless v.is_a?(String)

        case v
        when /\A-?\d+\z/ then v.to_i
        when /\A-?\d+(\.\d+)?([eE][+-]?\d+)?\z/ then v.to_f
        else error("conversion_error", "parseNumber", v, "not a numeric string")
        end
      end

      # --- object key enumeration (Tier 0: patterns can't enumerate unknown keys) ---

      def keys(v)
        return v if v.is_a?(ErrorVal)
        return error("type_error", "keys", v, "expected an object") unless v.is_a?(Hash)

        v.keys
      end

      def values(v)
        return v if v.is_a?(ErrorVal)
        return error("type_error", "values", v, "expected an object") unless v.is_a?(Hash)

        v.values
      end

      def get(v)
        return v if v.is_a?(ErrorVal)
        return error("argument_error", "get", v, "expected [_, _]") unless pair?(v)
        return error("type_error", "get", v, "expected an object") unless v[0].is_a?(Hash)
        return error("type_error", "get", v, "expected a string key") unless v[1].is_a?(String)
        return error("access_error", "get", v, "missing key") unless v[0].key?(v[1])

        v[0][v[1]]
      end

      def set(v)
        return v if v.is_a?(ErrorVal)
        return error("argument_error", "set", v, "expected [_, _, _]") unless v.is_a?(Array) && v.length == 3
        return error("type_error", "set", v, "expected an object") unless v[0].is_a?(Hash)
        return error("type_error", "set", v, "expected a string key") unless v[1].is_a?(String)

        v[0].merge(v[1] => v[2])
      end

      def to_object(v)
        return v if v.is_a?(ErrorVal)
        return error("type_error", "toObject", v, "expected an array") unless v.is_a?(Array)
        unless v.all? { |entry| pair?(entry) && entry[0].is_a?(String) }
          return error("type_error", "toObject", v, "expected [string, value] entries")
        end

        v.to_h
      end

      private

      # Type predicates, also reused as internal guards.

      def integer?(v)
        v.is_a?(Integer) && !boolean?(v)
      end

      def float?(v)
        v.is_a?(Float)
      end

      def numeric?(v)
        v.is_a?(Numeric) && !boolean?(v)
      end

      def string?(v)
        v.is_a?(String)
      end

      def boolean?(v)
        v == true || v == false
      end

      def array?(v)
        v.is_a?(Array)
      end

      def object?(v)
        v.is_a?(Hash)
      end

      def null?(v)
        v == NULL
      end

      def function?(v)
        v.is_a?(Func) || v.is_a?(NativeFunc)
      end

      def pair?(v)
        v.is_a?(Array) && v.length == 2
      end

      def non_finite?(v)
        v.is_a?(Float) && !v.finite?
      end

      # Build a standardized interpreter error (see docs/user/reference.md §6.5).
      def error(kind, name, v, message)
        ErrorVal.internal(
          kind: kind,
          location: "builtin #{name}",
          operation: name,
          input: v,
          message: message
        )
      end
    end
  end
end
