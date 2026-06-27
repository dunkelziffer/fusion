# frozen_string_literal: true

# The stdlib is ordinary Fusion code, so it cannot forge runtime errors.
# Instead each stdlib function signals bad input with a user error (`!`) whose
# payload mirrors the builtin error shape (docs/user/reference.md §6.5) with
# `origin` "stdlib", no `file` field and the function's own @-reference as
# `operation`.
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
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@range","status":0,"input":"hi","expected":["_ ? (m ? @Integer => [-1, m] | @lessThan)"]}')
    end

    it "errors on a negative integer (rather than recursing forever)" do
      expect_pipe
        .in("✅", "-1")
        .code("(x => x | @range)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@range","status":0,"input":-1,"expected":["_ ? (m ? @Integer => [-1, m] | @lessThan)"]}')
    end
  end

  describe "@map" do
    it "maps a function over a list" do
      expect_pipe
        .in("✅", "[1,2,3]")
        .code('(xs => {"f": @math/square, "xs": xs} | @map)')
        .out("✅", "[1,4,9]")
    end

    it "errors on a non-{f,xs} value" do
      expect_pipe
        .in("✅", "5")
        .code("(x => x | @map)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@map","status":0,"input":5,"expected":["{\"f\": _ ? @Function, \"xs\": _ ? @Array}"]}')
    end

    it "errors when a required key is missing" do
      expect_pipe
        .in("✅", "[1,2]")
        .code('(xs => {"xs": xs} | @map)')
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@map","status":0,"input":{"xs":[1,2]},"expected":["{\"f\": _ ? @Function, \"xs\": _ ? @Array}"]}')
    end

    it "errors when xs is present but not an array" do
      expect_pipe
        .in("✅", "null")
        .code('(_ => {"f": @negate, "xs": "nope"} | @map)')
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@map","status":0,"input":{"f":"<function>","xs":"nope"},"expected":["{\"f\": _ ? @Function, \"xs\": _ ? @Array}"]}')
    end

    it "validates f eagerly: a non-function f errors even when xs is empty" do
      expect_pipe
        .in("✅", "[]")
        .code('(xs => {"f": 5, "xs": xs} | @map)')
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@map","status":0,"input":{"f":5,"xs":[]},"expected":["{\"f\": _ ? @Function, \"xs\": _ ? @Array}"]}')
    end
  end

  # The error payloads are themselves serialized strictly (they are user errors),
  # so a function or non-finite number echoed into `input` would otherwise make
  # the whole error collapse into a serialization_error. Each function sanitizes
  # the echoed input — mirroring the interpreter's lenient placeholders — so the
  # intended error survives. See docs/lang/design.md §2.9.
  describe "unserializable inputs are sanitized in the echoed payload" do
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
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@range","status":0,"input":"<Infinity>","expected":["_ ? (m ? @Integer => [-1, m] | @lessThan)"]}')
    end

    it "@map of a {f} missing xs echoes the function placeholder" do
      expect_pipe
        .in("✅", "null")
        .code('(_ => {"f": @negate} | @map)')
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@map","status":0,"input":{"f":"<function>"},"expected":["{\"f\": _ ? @Function, \"xs\": _ ? @Array}"]}')
    end

    it "@map of a bare function echoes the function placeholder" do
      expect_pipe
        .in("✅", "null")
        .code("(_ => (y => y) | @map)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@map","status":0,"input":"<function>","expected":["{\"f\": _ ? @Function, \"xs\": _ ? @Array}"]}')
    end

    it "sanitizes deeply nested functions and non-finite numbers in the echoed input" do
      expect_pipe
        .in("✅", "null")
        .code('(_ => {"a": [1, (y => y), {"deep": @negate}], "b": [1e400]} | @map)')
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@map","status":0,"input":{"a":[1,"<function>",{"deep":"<function>"}],"b":["<Infinity>"]},"expected":["{\"f\": _ ? @Function, \"xs\": _ ? @Array}"]}')
    end
  end

  # An error from the supplied `f` bubbles through @map unchanged (it is not
  # @map's own failure). Its `file` is the call site of the operation that failed
  # — which is *inside* @map (stdlib internals, hence no `file`) when `f` is a bare
  # builtin, but the user's own source when `f`'s body invokes the operation.
  describe "an error from f keeps its own call site, not @map's" do
    it "leaves a bare-builtin f's error file-less (its call site is stdlib-internal)" do
      expect_pipe
        .in("✅", '[["a","b"]]')
        .code('(xs => {"f": @add, "xs": xs} | @map)')
        .out("❌", '{"kind":"argument_error","origin":"builtin","operation":"@add","status":0,"input":["a","b"],"expected":["[_ ? @Number, _ ? @Number]"]}')
    end

    it "keeps the user's file when f's own body invokes the failing operation" do
      expect_pipe
        .in("✅", "[1]")
        .code('(xs => {"f": (n => [n, "x"] | @add), "xs": xs} | @map)')
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@add","status":0,"input":[1,"x"],"expected":["[_ ? @Number, _ ? @Number]"]}')
    end
  end

  describe "@mapValues" do
    it "applies a function to each value, keeping the keys" do
      expect_pipe
        .in("✅", '{"a":1,"b":2,"c":3}')
        .code('(o => {"f": (n => [n, 2] | @multiply), "object": o} | @mapValues)')
        .out("✅", '{"a":2,"b":4,"c":6}')
    end

    it "is empty for the empty object" do
      expect_pipe
        .in("✅", "{}")
        .code('(o => {"f": (n => n), "object": o} | @mapValues)')
        .out("✅", "{}")
    end

    it "errors when object is not an object" do
      expect_pipe
        .in("✅", "5")
        .code('(o => {"f": (n => n), "object": o} | @mapValues)')
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@mapValues","status":0,"input":{"f":"<function>","object":5},"expected":["{\"f\": _ ? @Function, \"object\": _ ? @Object}"]}')
    end

    it "errors on a non-{f,object} value" do
      expect_pipe
        .in("✅", "5")
        .code("(x => x | @mapValues)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@mapValues","status":0,"input":5,"expected":["{\"f\": _ ? @Function, \"object\": _ ? @Object}"]}')
    end

    it "validates f eagerly: a non-function f errors even when the object is empty" do
      expect_pipe
        .in("✅", "{}")
        .code('(o => {"f": 5, "object": o} | @mapValues)')
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@mapValues","status":0,"input":{"f":5,"object":{}},"expected":["{\"f\": _ ? @Function, \"object\": _ ? @Object}"]}')
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
        .code('(xs => {"f": (false => false, _ => [1, "x"] | @lessThan), "xs": xs} | @all)')
        .out("✅", "false")
    end
  end
end
