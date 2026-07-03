# frozen_string_literal: true

# Built-in operations, reached via @name and applied to a value over a pipe.
#
# Each builtin is exercised for its happy paths and its failure payloads. A
# wrong input shape or type is an `argument_error` whose `expected` field
# lists the acceptable inputs as Fusion patterns. See docs/lang/design.md §2.9.
RSpec.describe "builtins" do
  describe "@size" do
    it "measures a string" do
      expect_pipe
        .in("✅", '"abc"')
        .code("(v => v | @size)")
        .out("✅", "3")
    end

    it "measures an array" do
      expect_pipe
        .in("✅", "[1,2,3]")
        .code("(v => v | @size)")
        .out("✅", "3")
    end

    it "measures an object by key count" do
      expect_pipe
        .in("✅", '{"a":1,"b":2}')
        .code("(v => v | @size)")
        .out("✅", "2")
    end

    it "is zero for the empty string" do
      expect_pipe
        .in("✅", '""')
        .code("(v => v | @size)")
        .out("✅", "0")
    end

    it "errors on a number" do
      expect_pipe
        .in("✅", "5")
        .code("(v => v | @size)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@size","status":0,"input":5,"expected":["_ ? @String","_ ? @Array","_ ? @Object"]}')
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

    it "errors when an element is not a string" do
      expect_pipe
        .in("✅", '[[1,2],","]')
        .code("(p => p | @join)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@join","status":0,"input":[[1,2],","],"expected":["[_ ? (xs => {\"xs\": xs, \"f\": @String} | @all), _ ? @String]"]}')
    end

    it "errors with argument_error on a non-pair" do
      expect_pipe
        .in("✅", '[["a"]]')
        .code("(p => p | @join)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@join","status":0,"input":[["a"]],"expected":["[_ ? (xs => {\"xs\": xs, \"f\": @String} | @all), _ ? @String]"]}')
    end
  end

  # @split is the inverse of @join: [string, separator]. It splits on the literal
  # separator, keeps empty fields, and treats an empty separator as "characters".
  describe "@split" do
    it "splits a string on a separator" do
      expect_pipe
        .in("✅", '["a-b-c","-"]')
        .code("(p => p | @split)")
        .out("✅", '["a","b","c"]')
    end

    it "keeps a trailing empty field" do
      expect_pipe
        .in("✅", '["a-b-","-"]')
        .code("(p => p | @split)")
        .out("✅", '["a","b",""]')
    end

    it "splits on a literal space (no whitespace-run special case)" do
      expect_pipe
        .in("✅", '["a b  c"," "]')
        .code("(p => p | @split)")
        .out("✅", '["a","b","","c"]')
    end

    it "splits into characters on an empty separator" do
      expect_pipe
        .in("✅", '["abc",""]')
        .code("(p => p | @split)")
        .out("✅", '["a","b","c"]')
    end

    it "is empty for the empty string" do
      expect_pipe
        .in("✅", '["","-"]')
        .code("(p => p | @split)")
        .out("✅", "[]")
    end

    it "errors when an element is not a string" do
      expect_pipe
        .in("✅", "[5,\"-\"]")
        .code("(p => p | @split)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@split","status":0,"input":[5,"-"],"expected":["[_ ? @String, _ ? @String]"]}')
    end

    it "errors with argument_error on a non-pair" do
      expect_pipe
        .in("✅", '["a-b"]')
        .code("(p => p | @split)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@split","status":0,"input":["a-b"],"expected":["[_ ? @String, _ ? @String]"]}')
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
        .out("❌", '{"kind":"conversion_error","origin":"builtin","file":"<inline>","operation":"@toString","status":0,"input":{"a":1},"message":"cannot stringify this value type"}')
    end

    it "errors with conversion_error on an array" do
      expect_pipe
        .in("✅", "[1,2]")
        .code("(v => v | @toString)")
        .out("❌", '{"kind":"conversion_error","origin":"builtin","file":"<inline>","operation":"@toString","status":0,"input":[1,2],"message":"cannot stringify this value type"}')
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
        .out("❌", '{"kind":"conversion_error","origin":"builtin","file":"<inline>","operation":"@parseNumber","status":0,"input":"abc","message":"not a numeric string"}')
    end

    it "errors on a non-string" do
      expect_pipe
        .in("✅", "5")
        .code("(s => s | @parseNumber)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@parseNumber","status":0,"input":5,"expected":["_ ? @String"]}')
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

    it "errors on a non-object" do
      expect_pipe
        .in("✅", "[1,2]")
        .code("(o => o | @keys)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@keys","status":0,"input":[1,2],"expected":["_ ? @Object"]}')
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

    it "errors on a non-object" do
      expect_pipe
        .in("✅", "5")
        .code("(o => o | @values)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@values","status":0,"input":5,"expected":["_ ? @Object"]}')
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
        .out("❌", '{"kind":"access_error","origin":"builtin","file":"<inline>","operation":"@get","status":0,"input":[{"a":1},"z"],"message":"missing key"}')
    end

    it "errors (bad index type) on a string key into a non-object" do
      expect_pipe
        .in("✅", "5")
        .code('(o => [o, "b"] | @get)')
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@get","status":0,"input":[5,"b"],"expected":["[_ ? @Array, _ ? @Integer]","[_ ? @Object, _ ? @String]"]}')
    end

    it "errors with argument_error on a non-pair" do
      expect_pipe
        .in("✅", "[1,2,3]")
        .code("(o => o | @get)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@get","status":0,"input":[1,2,3],"expected":["[_ ? @Array, _ ? @Integer]","[_ ? @Object, _ ? @String]"]}')
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
        .out("❌", '{"kind":"access_error","origin":"builtin","file":"<inline>","operation":"@get","status":0,"input":[[10,20],5],"message":"index out of range"}')
    end

    it "errors (bad index type) on a string index into an array" do
      expect_pipe
        .in("✅", "[1,2]")
        .code('(a => [a, "x"] | @get)')
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@get","status":0,"input":[[1,2],"x"],"expected":["[_ ? @Array, _ ? @Integer]","[_ ? @Object, _ ? @String]"]}')
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
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@set","status":0,"input":[{"a":1},"b"],"expected":["[_ ? @Array, _ ? @Integer, _]","[_ ? @Object, _ ? @String, _]"]}')
    end

    it "errors (bad index type) on a string key into a non-object" do
      expect_pipe
        .in("✅", "5")
        .code('(o => [o, "b", 2] | @set)')
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@set","status":0,"input":[5,"b",2],"expected":["[_ ? @Array, _ ? @Integer, _]","[_ ? @Object, _ ? @String, _]"]}')
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
        .out("❌", '{"kind":"access_error","origin":"builtin","file":"<inline>","operation":"@set","status":0,"input":[[10,20],5,99],"message":"index out of range"}')
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

    it "errors on a non-array" do
      expect_pipe
        .in("✅", "5")
        .code("(es => es | @toObject)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@toObject","status":0,"input":5,"expected":["_ ? (xs => {\"xs\": xs, \"f\": ([_ ? @String, _] => true)} | @all)"]}')
    end

    it "errors on a malformed entry" do
      expect_pipe
        .in("✅", '[["a",1],5]')
        .code("(es => es | @toObject)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@toObject","status":0,"input":[["a",1],5],"expected":["_ ? (xs => {\"xs\": xs, \"f\": ([_ ? @String, _] => true)} | @all)"]}')
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
