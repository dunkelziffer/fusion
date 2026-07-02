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
        define.call("not", method(:op_not))
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

        # `OP` bundles the operations slated for infix syntax sugar (a later
        # step). Reached as `@OP.and`, `@OP.sum`, … — a member access on this
        # builtin object, whose values are native functions.
        table["OP"] = {
          "sum"     => NativeFunc.new("OP.sum", method(:op_sum)),
          "product" => NativeFunc.new("OP.product", method(:op_product)),
          "negate"  => NativeFunc.new("OP.negate", method(:op_negate)),
          "invert"  => NativeFunc.new("OP.invert", method(:op_invert)),
          "equal"   => NativeFunc.new("OP.equal", method(:op_equal)),
          "compare" => NativeFunc.new("OP.compare", method(:op_compare)),
          "and"     => NativeFunc.new("OP.and", method(:op_and)),
          "or"      => NativeFunc.new("OP.or", method(:op_or)),
          "not"     => NativeFunc.new("OP.not", method(:op_not)),
        }
      end

      # --- arithmetic ---

      NUMBER_PAIR = ["[_ ? @Number, _ ? @Number]"].freeze
      NUMBER_ARRAY = ['_ ? (xs => {"xs": xs, "f": @Number} | @all)'].freeze

      # `add` is `@OP.sum` restricted to a numeric pair; it keeps its own shape
      # check so its `expected` stays the binary `[Number, Number]`.
      def add(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("add", v, NUMBER_PAIR) unless pair?(v) && numeric?(v[0]) && numeric?(v[1])

        op_sum(v)
      end

      def subtract(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("subtract", v, NUMBER_PAIR) unless pair?(v) && numeric?(v[0]) && numeric?(v[1])

        v[0] - v[1]
      end

      # `multiply` is `@OP.product` restricted to a numeric pair.
      def multiply(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("multiply", v, NUMBER_PAIR) unless pair?(v) && numeric?(v[0]) && numeric?(v[1])

        op_product(v)
      end

      def divide(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("divide", v, NUMBER_PAIR) unless pair?(v) && numeric?(v[0]) && numeric?(v[1])
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
        return argument_error("mod", v, NUMBER_PAIR) unless pair?(v) && numeric?(v[0]) && numeric?(v[1])
        return error("math_error", "mod", v, "modulo by zero") if v[1] == 0

        v[0] % v[1]
      end

      def negate(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("negate", v, ["_ ? @Number"]) unless numeric?(v)

        op_negate(v)
      end

      def floor(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("floor", v, ["_ ? @Number"]) unless numeric?(v)
        return error("math_error", "floor", v, "not a finite number") if non_finite?(v)

        v.floor
      end

      # --- comparison ---

      # `equals` is `@OP.equal` restricted to a pair (deep, exact).
      def equals(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("equals", v, ["[_, _]"]) unless pair?(v)

        op_equal(v)
      end

      # `lessThan` is the strictly-less case of `@OP.compare` on a pair.
      def less_than(v)
        return v if v.is_a?(ErrorVal)
        expected = ["[_ ? @Number, _ ? @Number]", "[_ ? @String, _ ? @String]"]
        return argument_error("lessThan", v, expected) unless pair?(v)

        a, b = v
        if (numeric?(a) && numeric?(b)) || (a.is_a?(String) && b.is_a?(String))
          op_compare(v) == -1
        else
          argument_error("lessThan", v, expected)
        end
      end

      # --- boolean ---

      # `and`/`or`/`not` judge truthiness (Ruby-style: `false` and `null` are
      # falsey, everything else truthy), not strict booleans, and always return a
      # boolean. `and`/`or` are the pair cases of `@OP.and`/`@OP.or`; `not` is
      # `@OP.not` verbatim (registered directly, no wrapper).
      def and_(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("and", v, ["[_, _]"]) unless pair?(v)

        op_and(v)
      end

      def or_(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("or", v, ["[_, _]"]) unless pair?(v)

        op_or(v)
      end

      # --- OP: the operations that will gain infix syntax sugar ---
      #
      # Reached as `@OP.sum`, `@OP.and`, … (a member access on the `OP` builtin
      # object). The arithmetic, boolean, and equality members take an array of
      # ANY length; the unary ones take a single value. `compare` returns
      # -1 / 0 / 1. The binary built-ins above derive from these.

      def op_sum(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("OP.sum", v, NUMBER_ARRAY) unless v.is_a?(Array) && v.all? { |x| numeric?(x) }

        v.sum(0)
      end

      def op_product(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("OP.product", v, NUMBER_ARRAY) unless v.is_a?(Array) && v.all? { |x| numeric?(x) }

        v.reduce(1, :*)
      end

      def op_negate(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("OP.negate", v, ["_ ? @Number"]) unless numeric?(v)

        -v
      end

      # The unary reciprocal 1/x, mirroring `@divide`: an integer result when x
      # divides 1 exactly (x is 1 or -1), a float otherwise; 0 is a math_error.
      def op_invert(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("OP.invert", v, ["_ ? @Number"]) unless numeric?(v)
        return error("math_error", "OP.invert", v, "division by zero") if v == 0

        v.is_a?(Integer) && (1 % v).zero? ? 1 / v : 1.0 / v
      end

      # Deep, exact equality across the whole array: true iff every element
      # equals the first (so 0 and 1 elements are vacuously equal). Any types.
      def op_equal(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("OP.equal", v, ["_ ? @Array"]) unless v.is_a?(Array)

        v.all? { |x| @interp.deep_equal?(v[0], x) }
      end

      # Order two numbers or two strings: -1, 0, or 1 (no deep equality). Built on
      # `<` rather than `<=>` so a NaN operand yields 0 (unordered), never Ruby's
      # `nil` — NaN is a reachable value (`Infinity - Infinity`).
      def op_compare(v)
        return v if v.is_a?(ErrorVal)
        expected = ["[_ ? @Number, _ ? @Number]", "[_ ? @String, _ ? @String]"]
        return argument_error("OP.compare", v, expected) unless pair?(v)

        a, b = v
        unless (numeric?(a) && numeric?(b)) || (a.is_a?(String) && b.is_a?(String))
          return argument_error("OP.compare", v, expected)
        end

        if a < b then -1
        elsif b < a then 1
        else 0
        end
      end

      def op_and(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("OP.and", v, ["_ ? @Array"]) unless v.is_a?(Array)

        v.all? { |x| @interp.truthy?(x) }
      end

      def op_or(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("OP.or", v, ["_ ? @Array"]) unless v.is_a?(Array)

        v.any? { |x| @interp.truthy?(x) }
      end

      def op_not(v)
        return v if v.is_a?(ErrorVal)

        !@interp.truthy?(v)
      end

      # --- strings and structure bridges ---

      def length(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("length", v, ["_ ? @String", "_ ? @Array", "_ ? @Object"]) unless v.is_a?(String) || v.is_a?(Array) || v.is_a?(Hash)

        v.length
      end

      def concat(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("concat", v, ["[_ ? @String, _ ? @String]"]) unless pair?(v) && v[0].is_a?(String) && v[1].is_a?(String)

        v[0] + v[1]
      end

      def chars(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("chars", v, ["_ ? @String"]) unless v.is_a?(String)

        v.chars
      end

      def join(v)
        return v if v.is_a?(ErrorVal)
        expected = ['[_ ? (xs => {"xs": xs, "f": @String} | @all), _ ? @String]']
        return argument_error("join", v, expected) unless pair?(v)

        array, separator = v
        unless array.is_a?(Array) && separator.is_a?(String) && array.all? { |item| item.is_a?(String) }
          return argument_error("join", v, expected)
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
        return argument_error("parseNumber", v, ["_ ? @String"]) unless v.is_a?(String)

        case v
        when /\A-?\d+\z/ then v.to_i
        when /\A-?\d+(\.\d+)?([eE][+-]?\d+)?\z/ then v.to_f
        else error("conversion_error", "parseNumber", v, "not a numeric string")
        end
      end

      # --- object key enumeration (Tier 0: patterns can't enumerate unknown keys) ---

      def keys(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("keys", v, ["_ ? @Object"]) unless v.is_a?(Hash)

        v.keys
      end

      def values(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("values", v, ["_ ? @Object"]) unless v.is_a?(Hash)

        v.values
      end

      # Read from an array (integer index, negative counts from the end) or an
      # object (string key) — mirroring the `[]` operator (reference §8).
      def get(v)
        return v if v.is_a?(ErrorVal)
        expected = ["[_ ? @Array, _ ? @Integer]", "[_ ? @Object, _ ? @String]"]
        return argument_error("get", v, expected) unless pair?(v)

        container, key = v
        if container.is_a?(Array) && key.is_a?(Integer)
          i = key.negative? ? container.length + key : key
          return container[i] if i >= 0 && i < container.length

          error("access_error", "get", v, "index out of range")
        elsif container.is_a?(Hash) && key.is_a?(String)
          return container[key] if container.key?(key)

          error("access_error", "get", v, "missing key")
        else
          argument_error("get", v, expected)
        end
      end

      # Return a new array/object with one entry set. An array index must already
      # exist (arrays are not extended); an object key may be new. Addressing
      # mirrors `@get` (array by integer index, object by string key).
      def set(v)
        return v if v.is_a?(ErrorVal)
        expected = ["[_ ? @Array, _ ? @Integer, _]", "[_ ? @Object, _ ? @String, _]"]
        return argument_error("set", v, expected) unless v.is_a?(Array) && v.length == 3

        container, key, value = v
        if container.is_a?(Array) && key.is_a?(Integer)
          i = key.negative? ? container.length + key : key
          return error("access_error", "set", v, "index out of range") unless i >= 0 && i < container.length

          container.dup.tap { |copy| copy[i] = value }
        elsif container.is_a?(Hash) && key.is_a?(String)
          container.merge(key => value)
        else
          argument_error("set", v, expected)
        end
      end

      def to_object(v)
        return v if v.is_a?(ErrorVal)
        # Each entry must be a [string, _] pair.
        expected = ['_ ? (xs => {"xs": xs, "f": ([_ ? @String, _] => true)} | @all)']
        unless v.is_a?(Array) && v.all? { |entry| pair?(entry) && entry[0].is_a?(String) }
          return argument_error("toObject", v, expected)
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

      # Build a standardized interpreter error carrying a human-readable
      # `message` (see docs/user/reference.md §6.5). Use this for failures that
      # aren't an input-shape mismatch (math, conversion, access). `operation`
      # is the builtin's own `@`-reference (`@#{name}`).
      def error(kind, name, v, message)
        ErrorVal.from_runtime(kind: kind, origin: "builtin", operation: "@#{name}", input: v, message: message)
      end

      # Build an `argument_error` describing the acceptable inputs as a list of
      # Fusion patterns. The input was unacceptable iff it matches none of them.
      def argument_error(name, v, expected)
        ErrorVal.from_runtime(kind: "argument_error", origin: "builtin", operation: "@#{name}", input: v, expected: expected)
      end
    end
  end
end
