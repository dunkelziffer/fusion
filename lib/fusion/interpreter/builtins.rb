# frozen_string_literal: true

# === Interpreter internals ===

module Fusion
  class Interpreter
    module Builtins
      extend self

      def install(table, interp)
        @interp = interp
        define = ->(name, fn) { table[name] = NativeFunc.new(name, fn) }

        # Irreducible primitives kept as built-ins. The sugar-target operators
        # (arithmetic/comparison/boolean) live in `@OP` below; their friendly
        # derived forms (`@lt`, `@gt`, `@truthy`, …) are stdlib files that build on
        # `@OP.*`, so they follow a per-directory `@OP` override. Numeric functions
        # (`round`, `divide`, `sin`, …) and constants (`pi`, `e`) live in `@math`.
        define.call("size", method(:size))
        define.call("join", method(:join))
        define.call("split", method(:split))
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

        # `OP` bundles the sugar-target operators as a shadowable builtin object,
        # reached as `@OP.sum`, `@OP.and`, … A directory can swap the operators by
        # placing an `OP.fsn` sibling that overrides members (reaching the
        # originals with `@@`); infix sugar and the derived stdlib helpers resolve
        # `@OP` per directory, so they follow the override.
        table["OP"] = {
          "sum"      => NativeFunc.new("OP.sum", method(:op_sum)),
          "product"  => NativeFunc.new("OP.product", method(:op_product)),
          "negate"   => NativeFunc.new("OP.negate", method(:op_negate)),
          "invert"   => NativeFunc.new("OP.invert", method(:op_invert)),
          "quotient" => NativeFunc.new("OP.quotient", method(:op_quotient)),
          "modulo"   => NativeFunc.new("OP.modulo", method(:op_modulo)),
          "equal"    => NativeFunc.new("OP.equal", method(:op_equal)),
          "compare"  => NativeFunc.new("OP.compare", method(:op_compare)),
          "and"      => NativeFunc.new("OP.and", method(:op_and)),
          "or"       => NativeFunc.new("OP.or", method(:op_or)),
          "not"      => NativeFunc.new("OP.not", method(:op_not)),
        }

        # `math` bundles numeric functions and constants, reached as `@math.round`,
        # `@math.pi`, … Like `@OP`, it is a shadowable builtin object. `pi`/`e` are
        # plain values; the rest are one-argument functions.
        table["math"] = {
          "round"  => NativeFunc.new("math.round", method(:math_round)),
          "floor"  => NativeFunc.new("math.floor", method(:math_floor)),
          "ceil"   => NativeFunc.new("math.ceil", method(:math_ceil)),
          "divide" => NativeFunc.new("math.divide", method(:math_divide)),
          "sign"   => NativeFunc.new("math.sign", method(:math_sign)),
          "abs"    => NativeFunc.new("math.abs", method(:math_abs)),
          "rand"   => NativeFunc.new("math.rand", method(:math_rand)),
          "sin"    => NativeFunc.new("math.sin", method(:math_sin)),
          "cos"    => NativeFunc.new("math.cos", method(:math_cos)),
          "exp"    => NativeFunc.new("math.exp", method(:math_exp)),
          "log"    => NativeFunc.new("math.log", method(:math_log)),
          "pow"    => NativeFunc.new("math.pow", method(:math_pow)),
          "sqrt"   => NativeFunc.new("math.sqrt", method(:math_sqrt)),
          "pi"     => Math::PI,
          "e"      => Math::E,
        }
      end

      # --- math (reached as `@math.round`, `@math.divide`, `@math.pi`, …) ---

      NUMBER_PAIR = ["[_ ? @Number, _ ? @Number]"].freeze
      NUMBER_ARRAY = ['_ ? (xs => {"xs": xs, "f": @Number} | @all)'].freeze
      NUMBER = ["_ ? @Number"].freeze

      # `round`/`floor`/`ceil` return an integer; a non-finite input is a math_error
      # (their Ruby forms raise `FloatDomainError` on it).
      def math_round(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("math.round", v, NUMBER) unless numeric?(v)
        return error("math_error", "math.round", v, "not a finite number") if non_finite?(v)

        v.round
      end

      def math_floor(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("math.floor", v, NUMBER) unless numeric?(v)
        return error("math_error", "math.floor", v, "not a finite number") if non_finite?(v)

        v.floor
      end

      def math_ceil(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("math.ceil", v, NUMBER) unless numeric?(v)
        return error("math_error", "math.ceil", v, "not a finite number") if non_finite?(v)

        v.ceil
      end

      # `divide` always yields a float. Integer division is `@OP.quotient`, the
      # remainder `@OP.modulo`.
      def math_divide(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("math.divide", v, NUMBER_PAIR) unless pair?(v) && numeric?(v[0]) && numeric?(v[1])
        return error("math_error", "math.divide", v, "division by zero") if v[1] == 0

        v[0].to_f / v[1]
      end

      # -1 / 0 / 1 (via `<`/`>`, so NaN → 0, never Ruby's `nil`).
      def math_sign(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("math.sign", v, NUMBER) unless numeric?(v)

        if v < 0 then -1
        elsif v > 0 then 1
        else 0
        end
      end

      def math_abs(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("math.abs", v, NUMBER) unless numeric?(v)

        v.abs
      end

      # `null` → a float in `[0.0, 1.0)`; a positive integer `n` → an integer in
      # `[0, n)`.
      def math_rand(v)
        return v if v.is_a?(ErrorVal)
        return rand if v == NULL
        return rand(v) if integer?(v) && v.positive?

        argument_error("math.rand", v, ["_ ? @Null", '_ ? (n ? @Integer => [0, n] | @OP.compare | (-1 => true))'])
      end

      def math_sin(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("math.sin", v, NUMBER) unless numeric?(v)

        Math.sin(v)
      end

      def math_cos(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("math.cos", v, NUMBER) unless numeric?(v)

        Math.cos(v)
      end

      def math_exp(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("math.exp", v, NUMBER) unless numeric?(v)

        Math.exp(v)
      end

      # Square root; the domain is non-negative numbers (a negative would be
      # complex).
      def math_sqrt(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("math.sqrt", v, NUMBER) unless numeric?(v)
        return error("math_error", "math.sqrt", v, "square root of a negative number") if v < 0

        Math.sqrt(v)
      end

      # Natural logarithm; the domain is positive numbers (`Math.log` raises on a
      # negative and gives `-Infinity` at 0).
      def math_log(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("math.log", v, NUMBER) unless numeric?(v)
        return error("math_error", "math.log", v, "log of a non-positive number") if v <= 0

        Math.log(v)
      end

      # `base ** exponent`: integer when the base and a non-negative integer
      # exponent are integers, a float otherwise. A negative base with a fractional
      # exponent (a complex result) is a math_error.
      def math_pow(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("math.pow", v, NUMBER_PAIR) unless pair?(v) && numeric?(v[0]) && numeric?(v[1])

        a, b = v
        result = a.is_a?(Integer) && b.is_a?(Integer) && !b.negative? ? a**b : a.to_f**b
        return error("math_error", "math.pow", v, "not in domain (complex result)") if result.is_a?(Complex)

        result
      end

      # --- OP: the sugar-target operators (reached as `@OP.sum`, `@OP.and`, …) ---
      #
      # The arithmetic, boolean, and equality members take an array of ANY length;
      # the unary ones take a single value; `compare` returns -1 / 0 / 1. The
      # friendly derived forms (`@lt`, `@gt`, `@truthy`, …) are stdlib files built on
      # these.

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

      # The unary reciprocal 1/x, always a float; 0 is a math_error.
      def op_invert(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("OP.invert", v, ["_ ? @Number"]) unless numeric?(v)
        return error("math_error", "OP.invert", v, "division by zero") if v == 0

        1.0 / v
      end

      INTEGER_PAIR = ["[_ ? @Integer, _ ? @Integer]"].freeze

      # Integer division and its remainder — integers only (`@divide` handles the
      # float case). Ruby's `/` and `%` agree in sign, so `q*b + r == a` holds.
      def op_quotient(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("OP.quotient", v, INTEGER_PAIR) unless pair?(v) && integer?(v[0]) && integer?(v[1])
        return error("math_error", "OP.quotient", v, "division by zero") if v[1] == 0

        v[0] / v[1]
      end

      def op_modulo(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("OP.modulo", v, INTEGER_PAIR) unless pair?(v) && integer?(v[0]) && integer?(v[1])
        return error("math_error", "OP.modulo", v, "modulo by zero") if v[1] == 0

        v[0] % v[1]
      end

      # Deep, exact equality across the whole array: true iff every element
      # equals the first (so 0 and 1 elements are vacuously equal). Any types.
      def op_equal(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("OP.equal", v, ["_ ? @Array"]) unless v.is_a?(Array)

        v.all? { |x| @interp.deep_equal?(v[0], x) }
      end

      COMPARE_PAIR = ["[_ ? @Number, _ ? @Number]", "[_ ? @String, _ ? @String]"].freeze

      # Order two numbers or two strings: -1, 0, or 1 (no deep equality). Built on
      # `<` rather than `<=>` so a NaN operand yields 0 (unordered), never Ruby's
      # `nil` — NaN is a reachable value (`Infinity - Infinity`).
      def op_compare(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("OP.compare", v, COMPARE_PAIR) unless pair?(v)

        a, b = v
        unless (numeric?(a) && numeric?(b)) || (a.is_a?(String) && b.is_a?(String))
          return argument_error("OP.compare", v, COMPARE_PAIR)
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

      def size(v)
        return v if v.is_a?(ErrorVal)
        return argument_error("size", v, ["_ ? @String", "_ ? @Array", "_ ? @Object"]) unless v.is_a?(String) || v.is_a?(Array) || v.is_a?(Hash)

        v.length
      end

      # `[items, separator]`: join an array of strings into one string. `@concat`
      # is the stdlib pair-case built on this.
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

      # `[string, separator]`: the inverse of `@join`. Splits on the LITERAL
      # separator (Ruby's `" "` whitespace special-case does not apply) and keeps
      # empty fields; an empty separator splits into characters. `@chars` is the
      # stdlib single-string case built on this.
      def split(v)
        return v if v.is_a?(ErrorVal)
        expected = ["[_ ? @String, _ ? @String]"]
        return argument_error("split", v, expected) unless pair?(v) && v[0].is_a?(String) && v[1].is_a?(String)

        string, separator = v
        return string.chars if separator.empty?

        string.split(Regexp.new(Regexp.escape(separator)), -1)
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
      # Read from an array (integer index, negative counts from the end) or an
      # object (string key) — the functional form of `[]` (reference §8), which
      # desugars to `@get`.
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
