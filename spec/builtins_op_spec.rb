# frozen_string_literal: true

# The `@OP` builtin bundles the operations slated for infix syntax sugar. Each is
# reached as a member access on the `OP` object (`@OP.sum`, `@OP.and`, …). Unlike
# their binary namesakes in builtins_spec.rb, the arithmetic/boolean/equality
# members take an array of ANY length, and `compare` returns -1 / 0 / 1.
#
# A wrong input shape or type is an `argument_error` whose `operation` is the
# member's own reference (`@OP.sum`) and whose `expected` lists the acceptable
# inputs as Fusion patterns.
RSpec.describe "@OP builtin" do
  describe "@OP.sum" do
    it "sums an array of arbitrary length" do
      expect_pipe
        .in("✅", "[1,2,3,4]")
        .code("(v => v | @OP.sum)")
        .out("✅", "10")
    end

    it "sums a pair, like @add" do
      expect_pipe
        .in("✅", "[1,2]")
        .code("(v => v | @OP.sum)")
        .out("✅", "3")
    end

    it "is 0 for the empty array" do
      expect_pipe
        .in("✅", "[]")
        .code("(v => v | @OP.sum)")
        .out("✅", "0")
    end

    it "produces a float when any element is a float" do
      expect_pipe
        .in("✅", "[1.5,2]")
        .code("(v => v | @OP.sum)")
        .out("✅", "3.5")
    end

    it "errors when an element is not a number" do
      expect_pipe
        .in("✅", '[1,"a"]')
        .code("(v => v | @OP.sum)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@OP.sum","status":0,"input":[1,"a"],"expected":["_ ? (xs => {\"xs\": xs, \"f\": @Number} | @all)"]}')
    end

    it "treats a boolean element as the wrong type" do
      expect_pipe
        .in("✅", "[true,1]")
        .code("(v => v | @OP.sum)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@OP.sum","status":0,"input":[true,1],"expected":["_ ? (xs => {\"xs\": xs, \"f\": @Number} | @all)"]}')
    end

    it "errors on a non-array" do
      expect_pipe
        .in("✅", "5")
        .code("(v => v | @OP.sum)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@OP.sum","status":0,"input":5,"expected":["_ ? (xs => {\"xs\": xs, \"f\": @Number} | @all)"]}')
    end
  end

  describe "@OP.product" do
    it "multiplies an array of arbitrary length" do
      expect_pipe
        .in("✅", "[2,3,4]")
        .code("(v => v | @OP.product)")
        .out("✅", "24")
    end

    it "multiplies a pair, like @multiply" do
      expect_pipe
        .in("✅", "[3,4]")
        .code("(v => v | @OP.product)")
        .out("✅", "12")
    end

    it "is 1 for the empty array" do
      expect_pipe
        .in("✅", "[]")
        .code("(v => v | @OP.product)")
        .out("✅", "1")
    end

    it "produces a float when any element is a float" do
      expect_pipe
        .in("✅", "[1.5,2]")
        .code("(v => v | @OP.product)")
        .out("✅", "3.0")
    end

    it "errors when an element is not a number" do
      expect_pipe
        .in("✅", '["a",2]')
        .code("(v => v | @OP.product)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@OP.product","status":0,"input":["a",2],"expected":["_ ? (xs => {\"xs\": xs, \"f\": @Number} | @all)"]}')
    end

    it "errors on a non-array" do
      expect_pipe
        .in("✅", "5")
        .code("(v => v | @OP.product)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@OP.product","status":0,"input":5,"expected":["_ ? (xs => {\"xs\": xs, \"f\": @Number} | @all)"]}')
    end
  end

  describe "@OP.negate" do
    it "negates a positive" do
      expect_pipe
        .in("✅", "5")
        .code("(v => v | @OP.negate)")
        .out("✅", "-5")
    end

    it "negates a float" do
      expect_pipe
        .in("✅", "2.5")
        .code("(v => v | @OP.negate)")
        .out("✅", "-2.5")
    end

    it "errors on a non-number" do
      expect_pipe
        .in("✅", '"x"')
        .code("(v => v | @OP.negate)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@OP.negate","status":0,"input":"x","expected":["_ ? @Number"]}')
    end
  end

  # @OP.invert always yields a float (never an integer), for consistency.
  describe "@OP.invert" do
    it "returns a float reciprocal" do
      expect_pipe
        .in("✅", "2")
        .code("(v => v | @OP.invert)")
        .out("✅", "0.5")
    end

    it "is a float even when x is a unit (1)" do
      expect_pipe
        .in("✅", "1")
        .code("(v => v | @OP.invert)")
        .out("✅", "1.0")
    end

    it "is a float for a negative unit (-1)" do
      expect_pipe
        .in("✅", "-1")
        .code("(v => v | @OP.invert)")
        .out("✅", "-1.0")
    end

    it "inverts a float" do
      expect_pipe
        .in("✅", "0.5")
        .code("(v => v | @OP.invert)")
        .out("✅", "2.0")
    end

    it "errors with math_error on zero" do
      expect_pipe
        .in("✅", "0")
        .code("(v => v | @OP.invert)")
        .out("❌", '{"kind":"math_error","origin":"builtin","file":"<inline>","operation":"@OP.invert","status":0,"input":0,"message":"division by zero"}')
    end

    it "errors with math_error on 0.0" do
      expect_pipe
        .in("✅", "0.0")
        .code("(v => v | @OP.invert)")
        .out("❌", '{"kind":"math_error","origin":"builtin","file":"<inline>","operation":"@OP.invert","status":0,"input":0.0,"message":"division by zero"}')
    end

    it "errors on a non-number" do
      expect_pipe
        .in("✅", '"x"')
        .code("(v => v | @OP.invert)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@OP.invert","status":0,"input":"x","expected":["_ ? @Number"]}')
    end
  end

  # @OP.quotient and @OP.modulo are integer division: a pair of integers only,
  # erroring on any non-integer. Ruby's `/` and `%` agree in sign (q*b + r == a).
  describe "@OP.quotient" do
    it "divides two integers, truncating toward negative infinity" do
      expect_pipe
        .in("✅", "[7,2]")
        .code("(v => v | @OP.quotient)")
        .out("✅", "3")
    end

    it "floors a negative quotient (matching @OP.modulo's sign)" do
      expect_pipe
        .in("✅", "[-7,2]")
        .code("(v => v | @OP.quotient)")
        .out("✅", "-4")
    end

    it "is exact when it divides evenly" do
      expect_pipe
        .in("✅", "[6,3]")
        .code("(v => v | @OP.quotient)")
        .out("✅", "2")
    end

    it "errors with math_error on division by zero" do
      expect_pipe
        .in("✅", "[7,0]")
        .code("(v => v | @OP.quotient)")
        .out("❌", '{"kind":"math_error","origin":"builtin","file":"<inline>","operation":"@OP.quotient","status":0,"input":[7,0],"message":"division by zero"}')
    end

    it "errors on a float operand (integers only)" do
      expect_pipe
        .in("✅", "[7.0,2]")
        .code("(v => v | @OP.quotient)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@OP.quotient","status":0,"input":[7.0,2],"expected":["[_ ? @Integer, _ ? @Integer]"]}')
    end

    it "errors on a non-pair" do
      expect_pipe
        .in("✅", "[7,2,1]")
        .code("(v => v | @OP.quotient)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@OP.quotient","status":0,"input":[7,2,1],"expected":["[_ ? @Integer, _ ? @Integer]"]}')
    end
  end

  describe "@OP.modulo" do
    it "takes a remainder of two integers" do
      expect_pipe
        .in("✅", "[7,3]")
        .code("(v => v | @OP.modulo)")
        .out("✅", "1")
    end

    it "follows the sign of the divisor (Ruby modulo)" do
      expect_pipe
        .in("✅", "[-7,3]")
        .code("(v => v | @OP.modulo)")
        .out("✅", "2")
    end

    it "is zero when evenly divisible" do
      expect_pipe
        .in("✅", "[8,4]")
        .code("(v => v | @OP.modulo)")
        .out("✅", "0")
    end

    it "errors with math_error on modulo by zero" do
      expect_pipe
        .in("✅", "[7,0]")
        .code("(v => v | @OP.modulo)")
        .out("❌", '{"kind":"math_error","origin":"builtin","file":"<inline>","operation":"@OP.modulo","status":0,"input":[7,0],"message":"modulo by zero"}')
    end

    it "errors on a float operand (integers only)" do
      expect_pipe
        .in("✅", "[7.5,2]")
        .code("(v => v | @OP.modulo)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@OP.modulo","status":0,"input":[7.5,2],"expected":["[_ ? @Integer, _ ? @Integer]"]}')
    end

    it "errors on a non-array" do
      expect_pipe
        .in("✅", "5")
        .code("(v => v | @OP.modulo)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@OP.modulo","status":0,"input":5,"expected":["[_ ? @Integer, _ ? @Integer]"]}')
    end
  end

  # @OP.equal is deep, exact (no numeric coercion, int ≠ float), across the whole
  # array: true iff every element equals the first. It accepts any element types.
  describe "@OP.equal" do
    it "is true when all elements are equal" do
      expect_pipe
        .in("✅", "[1,1,1]")
        .code("(v => v | @OP.equal)")
        .out("✅", "true")
    end

    it "is false when one element differs" do
      expect_pipe
        .in("✅", "[1,1,2]")
        .code("(v => v | @OP.equal)")
        .out("✅", "false")
    end

    it "compares a pair, like @eq" do
      expect_pipe
        .in("✅", "[1,2]")
        .code("(v => v | @OP.equal)")
        .out("✅", "false")
    end

    it "does not coerce a number to a string" do
      expect_pipe
        .in("✅", '[1,"1"]')
        .code("(v => v | @OP.equal)")
        .out("✅", "false")
    end

    it "treats an integer and the equal float as distinct (exact)" do
      expect_pipe
        .in("✅", "[1,1.0]")
        .code("(v => v | @OP.equal)")
        .out("✅", "false")
    end

    it "compares structurally (deep)" do
      expect_pipe
        .in("✅", "[[1,[2]],[1,[2]]]")
        .code("(v => v | @OP.equal)")
        .out("✅", "true")
    end

    it "is vacuously true for a single element" do
      expect_pipe
        .in("✅", "[5]")
        .code("(v => v | @OP.equal)")
        .out("✅", "true")
    end

    it "is vacuously true for the empty array" do
      expect_pipe
        .in("✅", "[]")
        .code("(v => v | @OP.equal)")
        .out("✅", "true")
    end

    it "errors on a non-array" do
      expect_pipe
        .in("✅", "5")
        .code("(v => v | @OP.equal)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@OP.equal","status":0,"input":5,"expected":["_ ? @Array"]}')
    end
  end

  # @OP.compare orders a pair of numbers or a pair of strings: -1 (first smaller),
  # 0 (equal), 1 (first bigger). No deep equality; same allowed inputs as @lt.
  describe "@OP.compare" do
    it "is -1 when the first number is smaller" do
      expect_pipe
        .in("✅", "[1,2]")
        .code("(v => v | @OP.compare)")
        .out("✅", "-1")
    end

    it "is 0 when the numbers are equal" do
      expect_pipe
        .in("✅", "[2,2]")
        .code("(v => v | @OP.compare)")
        .out("✅", "0")
    end

    it "is 1 when the first number is bigger" do
      expect_pipe
        .in("✅", "[3,1]")
        .code("(v => v | @OP.compare)")
        .out("✅", "1")
    end

    it "orders an integer and the equal float as equal (no deep equality)" do
      expect_pipe
        .in("✅", "[1,1.0]")
        .code("(v => v | @OP.compare)")
        .out("✅", "0")
    end

    it "compares strings lexicographically (smaller)" do
      expect_pipe
        .in("✅", '["a","b"]')
        .code("(v => v | @OP.compare)")
        .out("✅", "-1")
    end

    it "compares strings lexicographically (bigger)" do
      expect_pipe
        .in("✅", '["b","a"]')
        .code("(v => v | @OP.compare)")
        .out("✅", "1")
    end

    it "is 0 for equal strings" do
      expect_pipe
        .in("✅", '["a","a"]')
        .code("(v => v | @OP.compare)")
        .out("✅", "0")
    end

    it "errors on mixed types" do
      expect_pipe
        .in("✅", '[1,"a"]')
        .code("(v => v | @OP.compare)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@OP.compare","status":0,"input":[1,"a"],"expected":["[_ ? @Number, _ ? @Number]","[_ ? @String, _ ? @String]"]}')
    end

    it "errors on a non-pair array (too long)" do
      expect_pipe
        .in("✅", "[1,2,3]")
        .code("(v => v | @OP.compare)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@OP.compare","status":0,"input":[1,2,3],"expected":["[_ ? @Number, _ ? @Number]","[_ ? @String, _ ? @String]"]}')
    end

    it "errors on a non-pair array (too short)" do
      expect_pipe
        .in("✅", "[1]")
        .code("(v => v | @OP.compare)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@OP.compare","status":0,"input":[1],"expected":["[_ ? @Number, _ ? @Number]","[_ ? @String, _ ? @String]"]}')
    end
  end

  # @OP.and/@OP.or/@OP.not judge truthiness (false and null are falsey, everything
  # else — including 0 — is truthy) and always return a boolean.
  describe "@OP.and" do
    it "is true when every element is truthy (arbitrary length)" do
      expect_pipe
        .in("✅", "[true,true,true]")
        .code("(v => v | @OP.and)")
        .out("✅", "true")
    end

    it "is false when one element is falsey" do
      expect_pipe
        .in("✅", "[true,false]")
        .code("(v => v | @OP.and)")
        .out("✅", "false")
    end

    it "treats null as falsey" do
      expect_pipe
        .in("✅", "[true,null]")
        .code("(v => v | @OP.and)")
        .out("✅", "false")
    end

    it "treats a non-boolean truthy value (e.g. 0) as truthy" do
      expect_pipe
        .in("✅", "[true,0]")
        .code("(v => v | @OP.and)")
        .out("✅", "true")
    end

    it "is vacuously true for the empty array" do
      expect_pipe
        .in("✅", "[]")
        .code("(v => v | @OP.and)")
        .out("✅", "true")
    end

    it "errors on a non-array" do
      expect_pipe
        .in("✅", "5")
        .code("(v => v | @OP.and)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@OP.and","status":0,"input":5,"expected":["_ ? @Array"]}')
    end
  end

  describe "@OP.or" do
    it "is true when one element is truthy (arbitrary length)" do
      expect_pipe
        .in("✅", "[false,false,true]")
        .code("(v => v | @OP.or)")
        .out("✅", "true")
    end

    it "is false when every element is falsey" do
      expect_pipe
        .in("✅", "[false,false]")
        .code("(v => v | @OP.or)")
        .out("✅", "false")
    end

    it "treats null as falsey" do
      expect_pipe
        .in("✅", "[false,null]")
        .code("(v => v | @OP.or)")
        .out("✅", "false")
    end

    it "treats a non-boolean truthy value (e.g. 0) as truthy" do
      expect_pipe
        .in("✅", "[false,0]")
        .code("(v => v | @OP.or)")
        .out("✅", "true")
    end

    it "is vacuously false for the empty array" do
      expect_pipe
        .in("✅", "[]")
        .code("(v => v | @OP.or)")
        .out("✅", "false")
    end

    it "errors on a non-array" do
      expect_pipe
        .in("✅", "5")
        .code("(v => v | @OP.or)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@OP.or","status":0,"input":5,"expected":["_ ? @Array"]}')
    end
  end

  describe "@OP.not" do
    it "negates a truthy value to false" do
      expect_pipe
        .in("✅", "true")
        .code("(v => v | @OP.not)")
        .out("✅", "false")
    end

    it "negates a falsey value to true" do
      expect_pipe
        .in("✅", "false")
        .code("(v => v | @OP.not)")
        .out("✅", "true")
    end

    it "treats null as falsey, so @OP.not is true" do
      expect_pipe
        .in("✅", "null")
        .code("(v => v | @OP.not)")
        .out("✅", "true")
    end

    it "treats a non-boolean truthy value (e.g. 0) as truthy, so @OP.not is false" do
      expect_pipe
        .in("✅", "0")
        .code("(v => v | @OP.not)")
        .out("✅", "false")
    end
  end

  # @OP.get reads an array element by integer index (negatives count from the
  # end) or an object value by string key. @get is a thin wrapper over it.
  describe "@OP.get" do
    it "reads an array element by index" do
      expect_pipe
        .in("✅", "[10,20,30]")
        .code("(a => [a, 1] | @OP.get)")
        .out("✅", "20")
    end

    it "reads by a negative index from the end" do
      expect_pipe
        .in("✅", "[10,20,30]")
        .code("(a => [a, -1] | @OP.get)")
        .out("✅", "30")
    end

    it "reads an object value by key" do
      expect_pipe
        .in("✅", '{"a":1,"b":2}')
        .code('(o => [o, "b"] | @OP.get)')
        .out("✅", "2")
    end

    it "errors with access_error on a missing key" do
      expect_pipe
        .in("✅", '{"a":1}')
        .code('(o => [o, "z"] | @OP.get)')
        .out("❌", '{"kind":"access_error","origin":"builtin","file":"<inline>","operation":"@OP.get","status":0,"input":[{"a":1},"z"],"message":"missing key"}')
    end

    it "errors with access_error when an index is out of range" do
      expect_pipe
        .in("✅", "[10,20]")
        .code("(a => [a, 5] | @OP.get)")
        .out("❌", '{"kind":"access_error","origin":"builtin","file":"<inline>","operation":"@OP.get","status":0,"input":[[10,20],5],"message":"index out of range"}')
    end

    it "errors on a wrong-typed address" do
      expect_pipe
        .in("✅", "[1,2]")
        .code('(a => [a, "x"] | @OP.get)')
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@OP.get","status":0,"input":[[1,2],"x"],"expected":["[_ ? @Array, _ ? @Integer]","[_ ? @Object, _ ? @String]"]}')
    end
  end

  # Errors propagate through an OP member just like any builtin: an error input is
  # returned untouched (the member is never invoked on it).
  describe "error propagation" do
    it "passes a piped error straight through @OP.sum" do
      expect_pipe
        .in("✅", "null")
        .code("(_ => !42 | @OP.sum)")
        .out("❌", "42")
    end
  end
end
