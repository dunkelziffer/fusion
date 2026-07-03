# frozen_string_literal: true

RSpec.describe "stdlib error handling" do
  describe "@math/square" do
    it "squares an integer" do
      expect_pipe
        .in("✅", "5")
        .code("(x => x | @math/square)")
        .out("✅", "25")
    end

    it "errors on a non-integer (string)" do
      expect_pipe
        .in("✅", '"hi"')
        .code("(x => x | @math/square)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@math/square","status":0,"input":"hi","expected":["_ ? @Integer"]}')
    end

    it "errors on a float (square is integer-only)" do
      expect_pipe
        .in("✅", "2.5")
        .code("(x => x | @math/square)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@math/square","status":0,"input":2.5,"expected":["_ ? @Integer"]}')
    end
  end

  describe "@range" do
    it "builds [0, n) for a non-negative integer" do
      expect_pipe
        .in("✅", "3")
        .code("(x => x | @range)")
        .out("✅", "[0,1,2]")
    end

    it "is empty for 0" do
      expect_pipe
        .in("✅", "0")
        .code("(x => x | @range)")
        .out("✅", "[]")
    end

    it "errors on a non-integer" do
      expect_pipe
        .in("✅", '"hi"')
        .code("(x => x | @range)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@range","status":0,"input":"hi","expected":["_ ? (m ? @Integer => [m, -1] | @OP.compare | (1 => true))"]}')
    end

    it "errors on a negative integer (rather than recursing forever)" do
      expect_pipe
        .in("✅", "-1")
        .code("(x => x | @range)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@range","status":0,"input":-1,"expected":["_ ? (m ? @Integer => [m, -1] | @OP.compare | (1 => true))"]}')
    end
  end

  describe "@map" do
    it "maps a function over a list" do
      expect_pipe
        .in("✅", "[1,2,3]")
        .code('(xs => {"f": @math/square, "xs": xs} | @map)')
        .out("✅", "[1,4,9]")
    end

    # When xs is an object, @map transforms each value and keeps the keys (the
    # former @mapValues).
    it "maps over an object's values, keeping the keys" do
      expect_pipe
        .in("✅", '{"a":1,"b":2,"c":3}')
        .code('(o => {"f": (n => [n, 2] | @OP.product), "xs": o} | @map)')
        .out("✅", '{"a":2,"b":4,"c":6}')
    end

    it "is empty for the empty object" do
      expect_pipe
        .in("✅", "{}")
        .code('(o => {"f": (n => n), "xs": o} | @map)')
        .out("✅", "{}")
    end

    it "errors on a non-{f,xs} value" do
      expect_pipe
        .in("✅", "5")
        .code("(x => x | @map)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@map","status":0,"input":5,"expected":["{\"f\": _ ? @Function, \"xs\": _ ? @Array}","{\"f\": _ ? @Function, \"xs\": _ ? @Object}"]}')
    end

    it "errors when a required key is missing" do
      expect_pipe
        .in("✅", "[1,2]")
        .code('(xs => {"xs": xs} | @map)')
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@map","status":0,"input":{"xs":[1,2]},"expected":["{\"f\": _ ? @Function, \"xs\": _ ? @Array}","{\"f\": _ ? @Function, \"xs\": _ ? @Object}"]}')
    end

    it "errors when xs is present but not an array" do
      expect_pipe
        .in("✅", "null")
        .code('(_ => {"f": @OP.negate, "xs": "nope"} | @map)')
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@map","status":0,"input":{"f":"<function>","xs":"nope"},"expected":["{\"f\": _ ? @Function, \"xs\": _ ? @Array}","{\"f\": _ ? @Function, \"xs\": _ ? @Object}"]}')
    end

    it "validates f eagerly: a non-function f errors even when xs is empty" do
      expect_pipe
        .in("✅", "[]")
        .code('(xs => {"f": 5, "xs": xs} | @map)')
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@map","status":0,"input":{"f":5,"xs":[]},"expected":["{\"f\": _ ? @Function, \"xs\": _ ? @Array}","{\"f\": _ ? @Function, \"xs\": _ ? @Object}"]}')
    end

    it "validates f eagerly for an object too: a non-function f errors on an empty object" do
      expect_pipe
        .in("✅", "{}")
        .code('(o => {"f": 5, "xs": o} | @map)')
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@map","status":0,"input":{"f":5,"xs":{}},"expected":["{\"f\": _ ? @Function, \"xs\": _ ? @Array}","{\"f\": _ ? @Function, \"xs\": _ ? @Object}"]}')
    end
  end

  # "stdlib" errors are runtime errors, so they serialize leniently
  describe "unserializable inputs render as placeholders in the echoed payload" do
    it "@math/square of a function reports an argument_error, not a serialization_error" do
      expect_pipe
        .in("✅", "null")
        .code("(_ => (y => y) | @math/square)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@math/square","status":0,"input":"<function>","expected":["_ ? @Integer"]}')
    end

    it "@math/square of a non-finite number echoes the placeholder" do
      expect_pipe
        .in("✅", "null")
        .code("(_ => 1e400 | @math/square)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@math/square","status":0,"input":"<Infinity>","expected":["_ ? @Integer"]}')
    end

    it "@range of a non-finite number echoes the placeholder" do
      expect_pipe
        .in("✅", "null")
        .code("(_ => 1e400 | @range)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@range","status":0,"input":"<Infinity>","expected":["_ ? (m ? @Integer => [m, -1] | @OP.compare | (1 => true))"]}')
    end

    it "@map of a {f} missing xs echoes the function placeholder" do
      expect_pipe
        .in("✅", "null")
        .code('(_ => {"f": @OP.negate} | @map)')
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@map","status":0,"input":{"f":"<function>"},"expected":["{\"f\": _ ? @Function, \"xs\": _ ? @Array}","{\"f\": _ ? @Function, \"xs\": _ ? @Object}"]}')
    end

    it "@map of a bare function echoes the function placeholder" do
      expect_pipe
        .in("✅", "null")
        .code("(_ => (y => y) | @map)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@map","status":0,"input":"<function>","expected":["{\"f\": _ ? @Function, \"xs\": _ ? @Array}","{\"f\": _ ? @Function, \"xs\": _ ? @Object}"]}')
    end

    it "renders deeply nested functions and non-finite numbers in the echoed input" do
      expect_pipe
        .in("✅", "null")
        .code('(_ => {"a": [1, (y => y), {"deep": @OP.negate}], "b": [1e400]} | @map)')
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@map","status":0,"input":{"a":[1,"<function>",{"deep":"<function>"}],"b":["<Infinity>"]},"expected":["{\"f\": _ ? @Function, \"xs\": _ ? @Array}","{\"f\": _ ? @Function, \"xs\": _ ? @Object}"]}')
    end
  end

  # An error from the supplied `f` bubbles through @map unchanged. Its `file` is
  # the innermost *user* file. `@map`s stdlib frame is transparent.
  describe "an error from f reports the innermost user file, through @map" do
    it "attributes a bare-builtin f's error to the user call site" do
      expect_pipe
        .in("✅", '[["a","b"]]')
        .code('(xs => {"f": @OP.sum, "xs": xs} | @map)')
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@OP.sum","status":0,"input":["a","b"],"expected":["_ ? (xs => {\"xs\": xs, \"f\": @Number} | @all)"]}')
    end

    it "attributes a user-function f's error to the user call site too" do
      expect_pipe
        .in("✅", "[1]")
        .code('(xs => {"f": (n => [n, "x"] | @OP.sum), "xs": xs} | @map)')
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@OP.sum","status":0,"input":[1,"x"],"expected":["_ ? (xs => {\"xs\": xs, \"f\": @Number} | @all)"]}')
    end
  end


  describe "@all" do
    it "is true when every item satisfies the predicate" do
      expect_pipe
        .in("✅", '["a","b","c"]')
        .code('(xs => {"f": @String, "xs": xs} | @all)')
        .out("✅", "true")
    end

    it "is true for the empty array" do
      expect_pipe
        .in("✅", "[]")
        .code('(xs => {"f": @String, "xs": xs} | @all)')
        .out("✅", "true")
    end

    it "is false when an item fails the predicate" do
      expect_pipe
        .in("✅", '["a",1,"c"]')
        .code('(xs => {"f": @String, "xs": xs} | @all)')
        .out("✅", "false")
    end

    it "errors on a non-{f,xs} value" do
      expect_pipe
        .in("✅", "5")
        .code("(x => x | @all)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@all","status":0,"input":5,"expected":["{\"f\": _ ? @Function, \"xs\": _ ? @Array}"]}')
    end

    it "validates f eagerly: a non-function f errors even when xs is empty" do
      expect_pipe
        .in("✅", "[]")
        .code('(xs => {"f": 5, "xs": xs} | @all)')
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@all","status":0,"input":{"f":5,"xs":[]},"expected":["{\"f\": _ ? @Function, \"xs\": _ ? @Array}"]}')
    end

    # Proper recursion short-circuits: once an item is falsey the result is
    # false, and later items are never tested. Here the predicate would error on
    # the second item, so reaching it would surface that error instead of false.
    it "stops at the first falsey item without testing the rest" do
      expect_pipe
        .in("✅", "[false, true]")
        .code('(xs => {"f": (false => false, _ => [1, "x"] | @OP.compare), "xs": xs} | @all)')
        .out("✅", "false")
    end
  end

  # @concat and @chars are stdlib wrappers over the @join / @split builtins, so
  # their argument_errors report origin "stdlib".
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

    it "errors when an element is not a string" do
      expect_pipe
        .in("✅", '["a",1]')
        .code("(p => p | @concat)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@concat","status":0,"input":["a",1],"expected":["[_ ? @String, _ ? @String]"]}')
    end

    it "errors on a non-pair" do
      expect_pipe
        .in("✅", '["a"]')
        .code("(p => p | @concat)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@concat","status":0,"input":["a"],"expected":["[_ ? @String, _ ? @String]"]}')
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

    it "counts characters, not bytes (Unicode)" do
      expect_pipe
        .in("✅", '"héllo"')
        .code("(s => s | @chars)")
        .out("✅", '["h","é","l","l","o"]')
    end

    it "errors on a non-string" do
      expect_pipe
        .in("✅", "5")
        .code("(s => s | @chars)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@chars","status":0,"input":5,"expected":["_ ? @String"]}')
    end
  end
end
