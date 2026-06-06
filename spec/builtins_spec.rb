# frozen_string_literal: true

# Built-in operations, reached via @name and applied to a value over a pipe.
#
# Each builtin is exercised for its happy paths and its failure payloads. The
# argument_error vs type_error split is deliberate: argument_error means "wrong
# number" (not the pair/shape the op needs), type_error means a type mismatch.
# See docs/lang/design.md §2.9.
RSpec.describe "builtins" do
  describe "@add" do
    it "adds two integers" do
      expect_pipe
        .in("✅", "[1,2]")
        .code("(p => p | @add)")
        .out("✅", "3")
    end

    it "adds negatives" do
      expect_pipe
        .in("✅", "[-4,10]")
        .code("(p => p | @add)")
        .out("✅", "6")
    end

    it "produces a float when either side is a float" do
      expect_pipe
        .in("✅", "[1.5,2]")
        .code("(p => p | @add)")
        .out("✅", "3.5")
    end

    it "errors with type_error on a pair of the wrong type" do
      expect_pipe
        .in("✅", '["a","b"]')
        .code("(p => p | @add)")
        .out("❌", '{"kind":"type_error","location":"builtin add","operation":"add","input":["a","b"],"message":"expected numbers"}')
    end

    it "treats a boolean element as the wrong type" do
      expect_pipe
        .in("✅", "[true,1]")
        .code("(p => p | @add)")
        .out("❌", a_string_including('"kind":"type_error"', '"message":"expected numbers"'))
    end

    it "errors with argument_error on a non-pair array" do
      expect_pipe
        .in("✅", "[1,2,3]")
        .code("(p => p | @add)")
        .out("❌", '{"kind":"argument_error","location":"builtin add","operation":"add","input":[1,2,3],"message":"expected [_, _]"}')
    end

    it "errors with argument_error on a non-array" do
      expect_pipe
        .in("✅", "5")
        .code("(p => p | @add)")
        .out("❌", '{"kind":"argument_error","location":"builtin add","operation":"add","input":5,"message":"expected [_, _]"}')
    end
  end

  describe "@subtract" do
    it "subtracts" do
      expect_pipe
        .in("✅", "[5,3]")
        .code("(p => p | @subtract)")
        .out("✅", "2")
    end

    it "can go negative" do
      expect_pipe
        .in("✅", "[3,5]")
        .code("(p => p | @subtract)")
        .out("✅", "-2")
    end

    it "errors with type_error on a non-numeric pair" do
      expect_pipe
        .in("✅", '[1,"x"]')
        .code("(p => p | @subtract)")
        .out("❌", a_string_including('"kind":"type_error"', '"message":"expected numbers"'))
    end

    it "errors with argument_error on a non-pair" do
      expect_pipe
        .in("✅", "[1]")
        .code("(p => p | @subtract)")
        .out("❌", a_string_including('"kind":"argument_error"'))
    end
  end

  describe "@multiply" do
    it "multiplies" do
      expect_pipe
        .in("✅", "[3,4]")
        .code("(p => p | @multiply)")
        .out("✅", "12")
    end

    it "produces a float when either side is a float" do
      expect_pipe
        .in("✅", "[1.5,2]")
        .code("(p => p | @multiply)")
        .out("✅", "3.0")
    end

    it "errors with type_error on a non-numeric pair" do
      expect_pipe
        .in("✅", '["a",2]')
        .code("(p => p | @multiply)")
        .out("❌", a_string_including('"kind":"type_error"'))
    end

    it "errors with argument_error on a non-pair" do
      expect_pipe
        .in("✅", "[1,2,3]")
        .code("(p => p | @multiply)")
        .out("❌", a_string_including('"kind":"argument_error"'))
    end
  end

  describe "@divide" do
    it "returns an integer when evenly divisible" do
      expect_pipe
        .in("✅", "[6,3]")
        .code("(p => p | @divide)")
        .out("✅", "2")
    end

    it "returns a float otherwise" do
      expect_pipe
        .in("✅", "[7,2]")
        .code("(p => p | @divide)")
        .out("✅", "3.5")
    end

    it "returns a float for a non-integer negative result" do
      expect_pipe
        .in("✅", "[-6,4]")
        .code("(p => p | @divide)")
        .out("✅", "-1.5")
    end

    it "errors with math_error on division by zero" do
      expect_pipe
        .in("✅", "[1,0]")
        .code("(p => p | @divide)")
        .out("❌", '{"kind":"math_error","location":"builtin divide","operation":"divide","input":[1,0],"message":"division by zero"}')
    end

    it "errors with type_error on a non-numeric pair" do
      expect_pipe
        .in("✅", '[1,"x"]')
        .code("(p => p | @divide)")
        .out("❌", a_string_including('"kind":"type_error"', '"message":"expected numbers"'))
    end

    it "errors with argument_error on a non-pair" do
      expect_pipe
        .in("✅", "[1]")
        .code("(p => p | @divide)")
        .out("❌", a_string_including('"kind":"argument_error"'))
    end
  end

  describe "@mod" do
    it "takes a modulus" do
      expect_pipe
        .in("✅", "[7,3]")
        .code("(p => p | @mod)")
        .out("✅", "1")
    end

    it "is zero when evenly divisible" do
      expect_pipe
        .in("✅", "[8,4]")
        .code("(p => p | @mod)")
        .out("✅", "0")
    end

    it "errors with math_error on modulo by zero" do
      expect_pipe
        .in("✅", "[7,0]")
        .code("(p => p | @mod)")
        .out("❌", '{"kind":"math_error","location":"builtin mod","operation":"mod","input":[7,0],"message":"modulo by zero"}')
    end

    it "errors with argument_error on a non-pair" do
      expect_pipe
        .in("✅", "7")
        .code("(p => p | @mod)")
        .out("❌", '{"kind":"argument_error","location":"builtin mod","operation":"mod","input":7,"message":"expected [_, _]"}')
    end

    it "errors with type_error on a non-numeric pair" do
      expect_pipe
        .in("✅", '["a","b"]')
        .code("(p => p | @mod)")
        .out("❌", a_string_including('"kind":"type_error"'))
    end
  end

  describe "@negate" do
    it "negates a positive" do
      expect_pipe
        .in("✅", "5")
        .code("(n => n | @negate)")
        .out("✅", "-5")
    end

    it "negates a float" do
      expect_pipe
        .in("✅", "2.5")
        .code("(n => n | @negate)")
        .out("✅", "-2.5")
    end

    it "errors with type_error on a non-number" do
      expect_pipe
        .in("✅", '"x"')
        .code("(n => n | @negate)")
        .out("❌", '{"kind":"type_error","location":"builtin negate","operation":"negate","input":"x","message":"expected a number"}')
    end
  end

  describe "@floor" do
    it "floors a positive float to an integer" do
      expect_pipe
        .in("✅", "2.7")
        .code("(n => n | @floor)")
        .out("✅", "2")
    end

    it "floors a negative float towards minus infinity" do
      expect_pipe
        .in("✅", "-2.1")
        .code("(n => n | @floor)")
        .out("✅", "-3")
    end

    it "returns an integer unchanged" do
      expect_pipe
        .in("✅", "3")
        .code("(n => n | @floor)")
        .out("✅", "3")
    end

    it "errors with math_error on a non-finite number" do
      expect_pipe
        .in("✅", "null")
        .code("(_ => 1e400 | @floor)")
        .out("❌", a_string_including('"kind":"math_error"', '"location":"builtin floor"', '"message":"not a finite number"'))
    end

    it "errors with type_error on a non-number" do
      expect_pipe
        .in("✅", '"x"')
        .code("(n => n | @floor)")
        .out("❌", a_string_including('"kind":"type_error"', '"message":"expected a number"'))
    end
  end

  describe "@equals" do
    it "is true for equal integers" do
      expect_pipe
        .in("✅", "[1,1]")
        .code("(p => p | @equals)")
        .out("✅", "true")
    end

    it "is false for different integers" do
      expect_pipe
        .in("✅", "[1,2]")
        .code("(p => p | @equals)")
        .out("✅", "false")
    end

    it "does not coerce a number to a string" do
      expect_pipe
        .in("✅", '[1,"1"]')
        .code("(p => p | @equals)")
        .out("✅", "false")
    end

    it "treats an integer and the equal float as distinct (exact)" do
      expect_pipe
        .in("✅", "[1,1.0]")
        .code("(p => p | @equals)")
        .out("✅", "false")
    end

    it "compares structurally (deep)" do
      expect_pipe
        .in("✅", "[[1,[2]],[1,[2]]]")
        .code("(p => p | @equals)")
        .out("✅", "true")
    end

    it "errors with argument_error on a non-pair" do
      expect_pipe
        .in("✅", "[1,2,3]")
        .code("(p => p | @equals)")
        .out("❌", '{"kind":"argument_error","location":"builtin equals","operation":"equals","input":[1,2,3],"message":"expected [_, _]"}')
    end
  end

  describe "@lessThan" do
    it "compares two numbers" do
      expect_pipe
        .in("✅", "[1,2]")
        .code("(p => p | @lessThan)")
        .out("✅", "true")
    end

    it "is false when not strictly less" do
      expect_pipe
        .in("✅", "[1,1]")
        .code("(p => p | @lessThan)")
        .out("✅", "false")
    end

    it "compares two strings lexicographically" do
      expect_pipe
        .in("✅", '["a","b"]')
        .code("(p => p | @lessThan)")
        .out("✅", "true")
    end

    it "errors with type_error on mixed types" do
      expect_pipe
        .in("✅", '[1,"a"]')
        .code("(p => p | @lessThan)")
        .out("❌", '{"kind":"type_error","location":"builtin lessThan","operation":"lessThan","input":[1,"a"],"message":"expected two numbers or two strings"}')
    end

    it "errors with argument_error on a non-pair" do
      expect_pipe
        .in("✅", "[1]")
        .code("(p => p | @lessThan)")
        .out("❌", a_string_including('"kind":"argument_error"'))
    end
  end

  describe "@and" do
    it "is true only when both are true" do
      expect_pipe
        .in("✅", "[true,true]")
        .code("(p => p | @and)")
        .out("✅", "true")
    end

    it "is false when one is false" do
      expect_pipe
        .in("✅", "[true,false]")
        .code("(p => p | @and)")
        .out("✅", "false")
    end

    it "errors with type_error on a non-boolean element" do
      expect_pipe
        .in("✅", "[true,1]")
        .code("(p => p | @and)")
        .out("❌", '{"kind":"type_error","location":"builtin and","operation":"and","input":[true,1],"message":"expected booleans"}')
    end

    it "errors with argument_error on a non-pair" do
      expect_pipe
        .in("✅", "[true]")
        .code("(p => p | @and)")
        .out("❌", a_string_including('"kind":"argument_error"'))
    end
  end

  describe "@or" do
    it "is true when one is true" do
      expect_pipe
        .in("✅", "[false,true]")
        .code("(p => p | @or)")
        .out("✅", "true")
    end

    it "is false when both are false" do
      expect_pipe
        .in("✅", "[false,false]")
        .code("(p => p | @or)")
        .out("✅", "false")
    end

    it "errors with type_error on a non-boolean element" do
      expect_pipe
        .in("✅", "[1,true]")
        .code("(p => p | @or)")
        .out("❌", a_string_including('"kind":"type_error"', '"message":"expected booleans"'))
    end

    it "errors with argument_error on a non-pair" do
      expect_pipe
        .in("✅", "[false]")
        .code("(p => p | @or)")
        .out("❌", a_string_including('"kind":"argument_error"'))
    end
  end

  describe "@not" do
    it "negates true" do
      expect_pipe
        .in("✅", "true")
        .code("(b => b | @not)")
        .out("✅", "false")
    end

    it "negates false" do
      expect_pipe
        .in("✅", "false")
        .code("(b => b | @not)")
        .out("✅", "true")
    end

    it "errors with type_error on a non-boolean" do
      expect_pipe
        .in("✅", "1")
        .code("(b => b | @not)")
        .out("❌", '{"kind":"type_error","location":"builtin not","operation":"not","input":1,"message":"expected a boolean"}')
    end
  end

  describe "@length" do
    it "measures a string" do
      expect_pipe
        .in("✅", '"abc"')
        .code("(v => v | @length)")
        .out("✅", "3")
    end

    it "measures an array" do
      expect_pipe
        .in("✅", "[1,2,3]")
        .code("(v => v | @length)")
        .out("✅", "3")
    end

    it "measures an object by key count" do
      expect_pipe
        .in("✅", '{"a":1,"b":2}')
        .code("(v => v | @length)")
        .out("✅", "2")
    end

    it "is zero for the empty string" do
      expect_pipe
        .in("✅", '""')
        .code("(v => v | @length)")
        .out("✅", "0")
    end

    it "errors with type_error on a number" do
      expect_pipe
        .in("✅", "5")
        .code("(v => v | @length)")
        .out("❌", '{"kind":"type_error","location":"builtin length","operation":"length","input":5,"message":"expected a string, array, or object"}')
    end
  end

  describe "@concat" do
    it "concatenates two strings" do
      expect_pipe
        .in("✅", '["a","b"]')
        .code("(p => p | @concat)")
        .out("✅", '"ab"')
    end

    it "concatenates with an empty string" do
      expect_pipe
        .in("✅", '["x",""]')
        .code("(p => p | @concat)")
        .out("✅", '"x"')
    end

    it "errors with type_error when an element is not a string" do
      expect_pipe
        .in("✅", '["a",1]')
        .code("(p => p | @concat)")
        .out("❌", '{"kind":"type_error","location":"builtin concat","operation":"concat","input":["a",1],"message":"expected strings"}')
    end

    it "errors with argument_error on a non-pair" do
      expect_pipe
        .in("✅", '["a"]')
        .code("(p => p | @concat)")
        .out("❌", a_string_including('"kind":"argument_error"'))
    end
  end

  describe "@chars" do
    it "splits a string into its characters" do
      expect_pipe
        .in("✅", '"abc"')
        .code("(s => s | @chars)")
        .out("✅", '["a","b","c"]')
    end

    it "splits the empty string into an empty array" do
      expect_pipe
        .in("✅", '""')
        .code("(s => s | @chars)")
        .out("✅", "[]")
    end

    it "errors with type_error on a non-string" do
      expect_pipe
        .in("✅", "5")
        .code("(s => s | @chars)")
        .out("❌", '{"kind":"type_error","location":"builtin chars","operation":"chars","input":5,"message":"expected a string"}')
    end
  end

  describe "@join" do
    it "joins an array of strings with a separator" do
      expect_pipe
        .in("✅", '[["a","b"],"-"]')
        .code("(p => p | @join)")
        .out("✅", '"a-b"')
    end

    it "joins an empty array to the empty string" do
      expect_pipe
        .in("✅", '[[],","]')
        .code("(p => p | @join)")
        .out("✅", '""')
    end

    it "errors with type_error when an element is not a string" do
      expect_pipe
        .in("✅", '[[1,2],","]')
        .code("(p => p | @join)")
        .out("❌", '{"kind":"type_error","location":"builtin join","operation":"join","input":[[1,2],","],"message":"expected [array-of-strings, separator-string]"}')
    end

    it "errors with argument_error on a non-pair" do
      expect_pipe
        .in("✅", '[["a"]]')
        .code("(p => p | @join)")
        .out("❌", a_string_including('"kind":"argument_error"'))
    end
  end

  describe "@toString" do
    it "stringifies an integer" do
      expect_pipe
        .in("✅", "5")
        .code("(v => v | @toString)")
        .out("✅", '"5"')
    end

    it "stringifies a boolean" do
      expect_pipe
        .in("✅", "true")
        .code("(v => v | @toString)")
        .out("✅", '"true"')
    end

    it "stringifies null" do
      expect_pipe
        .in("✅", "null")
        .code("(v => v | @toString)")
        .out("✅", '"null"')
    end

    it "errors with conversion_error on an object" do
      expect_pipe
        .in("✅", '{"a":1}')
        .code("(v => v | @toString)")
        .out("❌", '{"kind":"conversion_error","location":"builtin toString","operation":"toString","input":{"a":1},"message":"cannot stringify this value type"}')
    end

    it "errors with conversion_error on an array" do
      expect_pipe
        .in("✅", "[1,2]")
        .code("(v => v | @toString)")
        .out("❌", a_string_including('"kind":"conversion_error"'))
    end
  end

  describe "@parseNumber" do
    it "parses an integer string" do
      expect_pipe
        .in("✅", '"5"')
        .code("(s => s | @parseNumber)")
        .out("✅", "5")
    end

    it "parses a float string" do
      expect_pipe
        .in("✅", '"2.5"')
        .code("(s => s | @parseNumber)")
        .out("✅", "2.5")
    end

    it "parses scientific notation as a float" do
      expect_pipe
        .in("✅", '"1e3"')
        .code("(s => s | @parseNumber)")
        .out("✅", "1000.0")
    end

    it "errors with conversion_error on a non-numeric string" do
      expect_pipe
        .in("✅", '"abc"')
        .code("(s => s | @parseNumber)")
        .out("❌", '{"kind":"conversion_error","location":"builtin parseNumber","operation":"parseNumber","input":"abc","message":"not a numeric string"}')
    end

    it "errors with type_error on a non-string" do
      expect_pipe
        .in("✅", "5")
        .code("(s => s | @parseNumber)")
        .out("❌", '{"kind":"type_error","location":"builtin parseNumber","operation":"parseNumber","input":5,"message":"expected a string"}')
    end
  end

  describe "@keys" do
    it "lists an object's keys" do
      expect_pipe
        .in("✅", '{"a":1,"b":2}')
        .code("(o => o | @keys)")
        .out("✅", '["a","b"]')
    end

    it "is empty for the empty object" do
      expect_pipe
        .in("✅", "{}")
        .code("(o => o | @keys)")
        .out("✅", "[]")
    end

    it "errors with type_error on a non-object" do
      expect_pipe
        .in("✅", "[1,2]")
        .code("(o => o | @keys)")
        .out("❌", '{"kind":"type_error","location":"builtin keys","operation":"keys","input":[1,2],"message":"expected an object"}')
    end
  end

  describe "@values" do
    it "lists an object's values" do
      expect_pipe
        .in("✅", '{"a":1,"b":2}')
        .code("(o => o | @values)")
        .out("✅", "[1,2]")
    end

    it "is empty for the empty object" do
      expect_pipe
        .in("✅", "{}")
        .code("(o => o | @values)")
        .out("✅", "[]")
    end

    it "errors with type_error on a non-object" do
      expect_pipe
        .in("✅", "5")
        .code("(o => o | @values)")
        .out("❌", '{"kind":"type_error","location":"builtin values","operation":"values","input":5,"message":"expected an object"}')
    end
  end

  describe "@get" do
    it "reads a key's value" do
      expect_pipe
        .in("✅", '{"a":1,"b":2}')
        .code('(o => [o, "b"] | @get)')
        .out("✅", "2")
    end

    it "errors with access_error on a missing key" do
      expect_pipe
        .in("✅", '{"a":1}')
        .code('(o => [o, "z"] | @get)')
        .out("❌", '{"kind":"access_error","location":"builtin get","operation":"get","input":[{"a":1},"z"],"message":"missing key"}')
    end

    it "errors with type_error (bad index type) on a string key into a non-object" do
      expect_pipe
        .in("✅", "5")
        .code('(o => [o, "b"] | @get)')
        .out("❌", '{"kind":"type_error","location":"builtin get","operation":"get","input":[5,"b"],"message":"bad index type"}')
    end

    it "errors with argument_error on a non-pair" do
      expect_pipe
        .in("✅", "[1,2,3]")
        .code("(o => o | @get)")
        .out("❌", '{"kind":"argument_error","location":"builtin get","operation":"get","input":[1,2,3],"message":"expected [_, _]"}')
    end

    it "reads an array element by integer index" do
      expect_pipe
        .in("✅", "[10,20,30]")
        .code("(a => [a, 1] | @get)")
        .out("✅", "20")
    end

    it "reads an array element by negative index (from the end)" do
      expect_pipe
        .in("✅", "[10,20,30]")
        .code("(a => [a, -1] | @get)")
        .out("✅", "30")
    end

    it "errors with access_error when an array index is out of range" do
      expect_pipe
        .in("✅", "[10,20]")
        .code("(a => [a, 5] | @get)")
        .out("❌", '{"kind":"access_error","location":"builtin get","operation":"get","input":[[10,20],5],"message":"index out of range"}')
    end

    it "errors with type_error (bad index type) on a string index into an array" do
      expect_pipe
        .in("✅", "[1,2]")
        .code('(a => [a, "x"] | @get)')
        .out("❌", '{"kind":"type_error","location":"builtin get","operation":"get","input":[[1,2],"x"],"message":"bad index type"}')
    end
  end

  describe "@set" do
    it "adds a new key, returning a new object" do
      expect_pipe
        .in("✅", '{"a":1}')
        .code('(o => [o, "b", 2] | @set)')
        .out("✅", '{"a":1,"b":2}')
    end

    it "overwrites an existing key" do
      expect_pipe
        .in("✅", '{"a":1}')
        .code('(o => [o, "a", 9] | @set)')
        .out("✅", '{"a":9}')
    end

    it "errors with argument_error when not a triple" do
      expect_pipe
        .in("✅", '{"a":1}')
        .code('(o => [o, "b"] | @set)')
        .out("❌", '{"kind":"argument_error","location":"builtin set","operation":"set","input":[{"a":1},"b"],"message":"expected [_, _, _]"}')
    end

    it "errors with type_error (bad index type) on a string key into a non-object" do
      expect_pipe
        .in("✅", "5")
        .code('(o => [o, "b", 2] | @set)')
        .out("❌", '{"kind":"type_error","location":"builtin set","operation":"set","input":[5,"b",2],"message":"bad index type"}')
    end

    it "replaces an array element by integer index, returning a new array" do
      expect_pipe
        .in("✅", "[10,20,30]")
        .code("(a => [a, 1, 99] | @set)")
        .out("✅", "[10,99,30]")
    end

    it "replaces an array element by negative index" do
      expect_pipe
        .in("✅", "[10,20,30]")
        .code("(a => [a, -1, 99] | @set)")
        .out("✅", "[10,20,99]")
    end

    it "errors with access_error when setting an out-of-range array index" do
      expect_pipe
        .in("✅", "[10,20]")
        .code("(a => [a, 5, 99] | @set)")
        .out("❌", '{"kind":"access_error","location":"builtin set","operation":"set","input":[[10,20],5,99],"message":"index out of range"}')
    end
  end

  describe "@toObject" do
    it "builds an object from [key, value] entries" do
      expect_pipe
        .in("✅", '[["a",1],["b",2]]')
        .code("(es => es | @toObject)")
        .out("✅", '{"a":1,"b":2}')
    end

    it "is empty for no entries" do
      expect_pipe
        .in("✅", "[]")
        .code("(es => es | @toObject)")
        .out("✅", "{}")
    end

    it "keeps the last value for a duplicate key" do
      expect_pipe
        .in("✅", '[["a",1],["a",9]]')
        .code("(es => es | @toObject)")
        .out("✅", '{"a":9}')
    end

    it "errors with type_error on a non-array" do
      expect_pipe
        .in("✅", "5")
        .code("(es => es | @toObject)")
        .out("❌", '{"kind":"type_error","location":"builtin toObject","operation":"toObject","input":5,"message":"expected an array"}')
    end

    it "errors with type_error on a malformed entry" do
      expect_pipe
        .in("✅", '[["a",1],5]')
        .code("(es => es | @toObject)")
        .out("❌", '{"kind":"type_error","location":"builtin toObject","operation":"toObject","input":[["a",1],5],"message":"expected [string, value] entries"}')
    end
  end

  describe "type predicates" do
    it "@Integer is true for an integer" do
      expect_pipe
        .in("✅", "5")
        .code("(x => x | @Integer)")
        .out("✅", "true")
    end

    it "@Integer is false for a float" do
      expect_pipe
        .in("✅", "2.0")
        .code("(x => x | @Integer)")
        .out("✅", "false")
    end

    it "@Integer is false for a boolean" do
      expect_pipe
        .in("✅", "true")
        .code("(x => x | @Integer)")
        .out("✅", "false")
    end

    it "@Float is true for a float" do
      expect_pipe
        .in("✅", "2.0")
        .code("(x => x | @Float)")
        .out("✅", "true")
    end

    it "@Float is false for an integer" do
      expect_pipe
        .in("✅", "5")
        .code("(x => x | @Float)")
        .out("✅", "false")
    end

    it "@Number is true for an integer" do
      expect_pipe
        .in("✅", "5")
        .code("(x => x | @Number)")
        .out("✅", "true")
    end

    it "@Number is true for a float" do
      expect_pipe
        .in("✅", "2.5")
        .code("(x => x | @Number)")
        .out("✅", "true")
    end

    it "@Number is false for a boolean" do
      expect_pipe
        .in("✅", "true")
        .code("(x => x | @Number)")
        .out("✅", "false")
    end

    it "@String is true for a string" do
      expect_pipe
        .in("✅", '"x"')
        .code("(x => x | @String)")
        .out("✅", "true")
    end

    it "@String is false for a number" do
      expect_pipe
        .in("✅", "5")
        .code("(x => x | @String)")
        .out("✅", "false")
    end

    it "@Boolean is true for a boolean" do
      expect_pipe
        .in("✅", "true")
        .code("(x => x | @Boolean)")
        .out("✅", "true")
    end

    it "@Boolean is false for a number" do
      expect_pipe
        .in("✅", "1")
        .code("(x => x | @Boolean)")
        .out("✅", "false")
    end

    it "@Array is true for an array" do
      expect_pipe
        .in("✅", "[]")
        .code("(x => x | @Array)")
        .out("✅", "true")
    end

    it "@Array is false for an object" do
      expect_pipe
        .in("✅", "{}")
        .code("(x => x | @Array)")
        .out("✅", "false")
    end

    it "@Object is true for an object" do
      expect_pipe
        .in("✅", "{}")
        .code("(x => x | @Object)")
        .out("✅", "true")
    end

    it "@Object is false for an array" do
      expect_pipe
        .in("✅", "[]")
        .code("(x => x | @Object)")
        .out("✅", "false")
    end

    it "@Null is true for null" do
      expect_pipe
        .in("✅", "null")
        .code("(x => x | @Null)")
        .out("✅", "true")
    end

    it "@Null is false for zero" do
      expect_pipe
        .in("✅", "0")
        .code("(x => x | @Null)")
        .out("✅", "false")
    end

    it "@Function is true for a function" do
      expect_pipe
        .in("✅", "null")
        .code("(_ => (y => y) | @Function)")
        .out("✅", "true")
    end

    it "@Function is false for a non-function" do
      expect_pipe
        .in("✅", "5")
        .code("(x => x | @Function)")
        .out("✅", "false")
    end

    it "@NonFinite is true for an overflowed float" do
      expect_pipe
        .in("✅", "null")
        .code("(_ => 1e400 | @NonFinite)")
        .out("✅", "true")
    end

    it "@NonFinite is false for a finite number" do
      expect_pipe
        .in("✅", "2.5")
        .code("(x => x | @NonFinite)")
        .out("✅", "false")
    end

    it "@NonFinite is false for a non-number" do
      expect_pipe
        .in("✅", '"hi"')
        .code("(x => x | @NonFinite)")
        .out("✅", "false")
    end
  end
end
