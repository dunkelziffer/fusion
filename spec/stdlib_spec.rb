# frozen_string_literal: true

# The stdlib is ordinary Fusion code, so it cannot forge interpreter-internal
# errors. Instead each stdlib function signals bad input with a user error (`!`)
# whose payload mirrors the builtin error shape (kind/location/operation/input/
# message), with `location: "stdlib X"`. See docs/lang/design.md §2.9.
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
        .out("❌", '{"kind":"type_error","location":"stdlib square.fsn","operation":"square","input":"hi","message":"expected an integer"}')
    end

    it "errors on a float (square is integer-only)" do
      expect_pipe
        .in("✅", "2.5")
        .code("(x => x | @math/square)")
        .out("❌", '{"kind":"type_error","location":"stdlib square.fsn","operation":"square","input":2.5,"message":"expected an integer"}')
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
        .out("❌", '{"kind":"type_error","location":"stdlib range.fsn","operation":"range","input":"hi","message":"expected a non-negative integer"}')
    end

    it "errors on a negative integer (rather than recursing forever)" do
      expect_pipe
        .in("✅", "-1")
        .code("(x => x | @range)")
        .out("❌", '{"kind":"type_error","location":"stdlib range.fsn","operation":"range","input":-1,"message":"expected a non-negative integer"}')
    end
  end

  describe "@map" do
    it "maps a function over a list" do
      expect_pipe
        .in("✅", "[1,2,3]")
        .code('(xs => {"f": @math/square, "xs": xs} | @map)')
        .out("✅", "[1,4,9]")
    end

    it "errors with argument_error on a non-{f,xs} value" do
      expect_pipe
        .in("✅", "5")
        .code("(x => x | @map)")
        .out("❌", '{"kind":"argument_error","location":"stdlib map.fsn","operation":"map","input":5,"message":"expected {\"f\": _, \"xs\": _}"}')
    end

    it "errors with argument_error when a required key is missing" do
      expect_pipe
        .in("✅", "[1,2]")
        .code('(xs => {"xs": xs} | @map)')
        .out("❌", '{"kind":"argument_error","location":"stdlib map.fsn","operation":"map","input":{"xs":[1,2]},"message":"expected {\"f\": _, \"xs\": _}"}')
    end

    it "errors with type_error when xs is present but not an array" do
      expect_pipe
        .in("✅", "null")
        .code('(_ => {"f": @negate, "xs": "nope"} | @map)')
        .out("❌", '{"kind":"type_error","location":"stdlib map.fsn","operation":"map","input":"nope","message":"expected an array"}')
    end
  end

  # The error payloads are themselves serialized strictly (they are user errors),
  # so a function or non-finite number echoed into `input` would otherwise make
  # the whole error collapse into a serialization_error. Each function sanitizes
  # the echoed input — mirroring the interpreter's lenient placeholders — so the
  # intended error survives. See docs/lang/design.md §2.9.
  describe "unserializable inputs are sanitized in the echoed payload" do
    it "@math/square of a function reports a type_error, not a serialization_error" do
      expect_pipe
        .in("✅", "null")
        .code("(_ => (y => y) | @math/square)")
        .out("❌", '{"kind":"type_error","location":"stdlib square.fsn","operation":"square","input":"<function>","message":"expected an integer"}')
    end

    it "@math/square of a non-finite number echoes the placeholder" do
      expect_pipe
        .in("✅", "null")
        .code("(_ => 1e400 | @math/square)")
        .out("❌", '{"kind":"type_error","location":"stdlib square.fsn","operation":"square","input":"<Infinity>","message":"expected an integer"}')
    end

    it "@range of a non-finite number echoes the placeholder" do
      expect_pipe
        .in("✅", "null")
        .code("(_ => 1e400 | @range)")
        .out("❌", '{"kind":"type_error","location":"stdlib range.fsn","operation":"range","input":"<Infinity>","message":"expected a non-negative integer"}')
    end

    it "@map of a {f} missing xs echoes the function placeholder" do
      expect_pipe
        .in("✅", "null")
        .code('(_ => {"f": @negate} | @map)')
        .out("❌", '{"kind":"argument_error","location":"stdlib map.fsn","operation":"map","input":{"f":"<function>"},"message":"expected {\"f\": _, \"xs\": _}"}')
    end

    it "@map of a bare function echoes the function placeholder" do
      expect_pipe
        .in("✅", "null")
        .code("(_ => (y => y) | @map)")
        .out("❌", '{"kind":"argument_error","location":"stdlib map.fsn","operation":"map","input":"<function>","message":"expected {\"f\": _, \"xs\": _}"}')
    end

    it "sanitizes deeply nested functions and non-finite numbers in the echoed input" do
      expect_pipe
        .in("✅", "null")
        .code('(_ => {"a": [1, (y => y), {"deep": @negate}], "b": [1e400]} | @map)')
        .out("❌", '{"kind":"argument_error","location":"stdlib map.fsn","operation":"map","input":{"a":[1,"<function>",{"deep":"<function>"}],"b":["<Infinity>"]},"message":"expected {\"f\": _, \"xs\": _}"}')
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
        .out("❌", '{"kind":"argument_error","location":"stdlib mapValues.fsn","operation":"mapValues","input":{"f":"<function>","object":5},"message":"expected {\"f\": _, \"object\": _}"}')
    end

    it "errors with argument_error on a non-{f,object} value" do
      expect_pipe
        .in("✅", "5")
        .code("(x => x | @mapValues)")
        .out("❌", '{"kind":"argument_error","location":"stdlib mapValues.fsn","operation":"mapValues","input":5,"message":"expected {\"f\": _, \"object\": _}"}')
    end
  end

  describe "@truthy / @falsey" do
    {
      "0"     => ["true",  "false"], # numbers are truthy, even zero
      '""'    => ["true",  "false"], # strings are truthy, even empty
      "[]"    => ["true",  "false"], # arrays are truthy, even empty
      "false" => ["false", "true"],
      "null"  => ["false", "true"],
    }.each do |input, (truthy, falsey)|
      it "classifies #{input} as truthy=#{truthy}" do
        expect_pipe.in("✅", input).code("@truthy").out("✅", truthy)
      end

      it "classifies #{input} as falsey=#{falsey}" do
        expect_pipe.in("✅", input).code("@falsey").out("✅", falsey)
      end
    end

    it "propagates an error input (no clause matches it)" do
      expect_pipe
        .in("❌", '"boom"')
        .code("@truthy")
        .out("❌", '"boom"')
    end
  end
end
