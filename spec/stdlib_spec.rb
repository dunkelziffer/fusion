# frozen_string_literal: true

RSpec.describe "stdlib error handling" do
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
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@range","status":0,"input":"hi","expected":["_ ? (m ? @Integer => [m, 0] | @OP.compare | @gte)"]}')
    end

    it "errors on a negative integer (rather than recursing forever)" do
      expect_pipe
        .in("✅", "-1")
        .code("(x => x | @range)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@range","status":0,"input":-1,"expected":["_ ? (m ? @Integer => [m, 0] | @OP.compare | @gte)"]}')
    end
  end

  describe "@map" do
    it "maps a function over a list" do
      expect_pipe
        .in("✅", "[1,2,3]")
        .code('(xs => {"f": (n => [n, n] | @OP.product), "c": xs} | @map)')
        .out("✅", "[1,4,9]")
    end

    # When c is an object, @map transforms each value and keeps the keys (the
    # former @mapValues).
    it "maps over an object's values, keeping the keys" do
      expect_pipe
        .in("✅", '{"a":1,"b":2,"c":3}')
        .code('(o => {"f": (n => [n, 2] | @OP.product), "c": o} | @map)')
        .out("✅", '{"a":2,"b":4,"c":6}')
    end

    it "is empty for the empty object" do
      expect_pipe
        .in("✅", "{}")
        .code('(o => {"f": (n => n), "c": o} | @map)')
        .out("✅", "{}")
    end

    it "errors on a non-{f,c} value" do
      expect_pipe
        .in("✅", "5")
        .code("(x => x | @map)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@map","status":0,"input":5,"expected":["{\"f\": _ ? @Function, \"c\": _ ? @Array}","{\"f\": _ ? @Function, \"c\": _ ? @Object}"]}')
    end

    it "errors when a required key is missing" do
      expect_pipe
        .in("✅", "[1,2]")
        .code('(xs => {"c": xs} | @map)')
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@map","status":0,"input":{"c":[1,2]},"expected":["{\"f\": _ ? @Function, \"c\": _ ? @Array}","{\"f\": _ ? @Function, \"c\": _ ? @Object}"]}')
    end

    it "errors when c is present but not an array" do
      expect_pipe
        .in("✅", "null")
        .code('(_ => {"f": @OP.negate, "c": "nope"} | @map)')
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@map","status":0,"input":{"f":"<function>","c":"nope"},"expected":["{\"f\": _ ? @Function, \"c\": _ ? @Array}","{\"f\": _ ? @Function, \"c\": _ ? @Object}"]}')
    end

    it "validates f eagerly: a non-function f errors even when c is empty" do
      expect_pipe
        .in("✅", "[]")
        .code('(xs => {"f": 5, "c": xs} | @map)')
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@map","status":0,"input":{"f":5,"c":[]},"expected":["{\"f\": _ ? @Function, \"c\": _ ? @Array}","{\"f\": _ ? @Function, \"c\": _ ? @Object}"]}')
    end

    it "validates f eagerly for an object too: a non-function f errors on an empty object" do
      expect_pipe
        .in("✅", "{}")
        .code('(o => {"f": 5, "c": o} | @map)')
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@map","status":0,"input":{"f":5,"c":{}},"expected":["{\"f\": _ ? @Function, \"c\": _ ? @Array}","{\"f\": _ ? @Function, \"c\": _ ? @Object}"]}')
    end
  end

  # "stdlib" errors are runtime errors, so they serialize leniently
  describe "unserializable inputs render as placeholders in the echoed payload" do
    it "@range of a non-finite number echoes the placeholder" do
      expect_pipe
        .in("✅", "null")
        .code("(_ => 1e400 | @range)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@range","status":0,"input":"<Infinity>","expected":["_ ? (m ? @Integer => [m, 0] | @OP.compare | @gte)"]}')
    end

    it "@map of a {f} missing c echoes the function placeholder" do
      expect_pipe
        .in("✅", "null")
        .code('(_ => {"f": @OP.negate} | @map)')
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@map","status":0,"input":{"f":"<function>"},"expected":["{\"f\": _ ? @Function, \"c\": _ ? @Array}","{\"f\": _ ? @Function, \"c\": _ ? @Object}"]}')
    end

    it "@map of a bare function echoes the function placeholder" do
      expect_pipe
        .in("✅", "null")
        .code("(_ => (y => y) | @map)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@map","status":0,"input":"<function>","expected":["{\"f\": _ ? @Function, \"c\": _ ? @Array}","{\"f\": _ ? @Function, \"c\": _ ? @Object}"]}')
    end

    it "renders deeply nested functions and non-finite numbers in the echoed input" do
      expect_pipe
        .in("✅", "null")
        .code('(_ => {"a": [1, (y => y), {"deep": @OP.negate}], "b": [1e400]} | @map)')
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@map","status":0,"input":{"a":[1,"<function>",{"deep":"<function>"}],"b":["<Infinity>"]},"expected":["{\"f\": _ ? @Function, \"c\": _ ? @Array}","{\"f\": _ ? @Function, \"c\": _ ? @Object}"]}')
    end
  end

  # An error from the supplied `f` bubbles through @map unchanged. Its `file` is
  # the innermost *user* file. `@map`s stdlib frame is transparent.
  describe "an error from f reports the innermost user file, through @map" do
    it "attributes a bare-builtin f's error to the user call site" do
      expect_pipe
        .in("✅", '[["a","b"]]')
        .code('(xs => {"f": @OP.sum, "c": xs} | @map)')
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@OP.sum","status":0,"input":["a","b"],"expected":["_ ? (xs => {\"c\": xs, \"f\": @Number} | @all)"]}')
    end

    it "attributes a user-function f's error to the user call site too" do
      expect_pipe
        .in("✅", "[1]")
        .code('(xs => {"f": (n => [n, "x"] | @OP.sum), "c": xs} | @map)')
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@OP.sum","status":0,"input":[1,"x"],"expected":["_ ? (xs => {\"c\": xs, \"f\": @Number} | @all)"]}')
    end
  end


  describe "@all" do
    it "is true when every item satisfies the predicate" do
      expect_pipe
        .in("✅", '["a","b","c"]')
        .code('(xs => {"f": @String, "c": xs} | @all)')
        .out("✅", "true")
    end

    it "is true for the empty array" do
      expect_pipe
        .in("✅", "[]")
        .code('(xs => {"f": @String, "c": xs} | @all)')
        .out("✅", "true")
    end

    it "is false when an item fails the predicate" do
      expect_pipe
        .in("✅", '["a",1,"c"]')
        .code('(xs => {"f": @String, "c": xs} | @all)')
        .out("✅", "false")
    end

    # Like @map/@filter, @all is polymorphic on c: an object is tested by its values.
    it "is true when every value of an object satisfies the predicate" do
      expect_pipe
        .in("✅", '{"a":"x","b":"y"}')
        .code('(o => {"f": @String, "c": o} | @all)')
        .out("✅", "true")
    end

    it "is false when an object value fails the predicate" do
      expect_pipe
        .in("✅", '{"a":"x","b":1}')
        .code('(o => {"f": @String, "c": o} | @all)')
        .out("✅", "false")
    end

    it "is true for the empty object" do
      expect_pipe
        .in("✅", "{}")
        .code('(o => {"f": @String, "c": o} | @all)')
        .out("✅", "true")
    end

    it "errors on a non-{f,c} value" do
      expect_pipe
        .in("✅", "5")
        .code("(x => x | @all)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@all","status":0,"input":5,"expected":["{\"f\": _ ? @Function, \"c\": _ ? @Array}","{\"f\": _ ? @Function, \"c\": _ ? @Object}"]}')
    end

    it "validates f eagerly: a non-function f errors even when c is empty" do
      expect_pipe
        .in("✅", "[]")
        .code('(xs => {"f": 5, "c": xs} | @all)')
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@all","status":0,"input":{"f":5,"c":[]},"expected":["{\"f\": _ ? @Function, \"c\": _ ? @Array}","{\"f\": _ ? @Function, \"c\": _ ? @Object}"]}')
    end

    # Proper recursion short-circuits: once an item is falsey the result is
    # false, and later items are never tested. Here the predicate would error on
    # the second item, so reaching it would surface that error instead of false.
    it "stops at the first falsey item without testing the rest" do
      expect_pipe
        .in("✅", "[false, true]")
        .code('(xs => {"f": (false => false, _ => [1, "x"] | @OP.compare), "c": xs} | @all)')
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

  # The comparison helpers interpret an @OP.compare result (-1 / 0 / 1); the caller
  # pipes a pair through @OP.compare first, so the compare step follows a per-directory
  # @OP override while the helper itself stays stable and shadow-independent.
  describe "comparison helpers (read off @OP.compare)" do
    it "@lt / @gt / @lte / @gte map a compare result to a boolean" do
      expect_pipe
        .in("✅", "[1,2]")
        .code('(p => p | @OP.compare | (c => [c | @lt, c | @gt, c | @lte, c | @gte]))')
        .out("✅", "[true,false,true,false]")
    end

    it "@lte and @gte are inclusive at equality (compare is 0)" do
      expect_pipe
        .in("✅", "[2,2]")
        .code('(p => p | @OP.compare | (c => [c | @lt, c | @gt, c | @lte, c | @gte]))')
        .out("✅", "[false,false,true,true]")
    end

    # A partial order's `compare` may report `null` (incomparable); each helper
    # passes that through as `null` rather than forcing a boolean.
    it "propagates a null compare result as null" do
      expect_pipe
        .in("✅", "null")
        .code('(c => [c | @lt, c | @gt, c | @lte, c | @gte])')
        .out("✅", "[null,null,null,null]")
    end

    it "raises a stdlib argument_error on a value that is not a compare result" do
      expect_pipe
        .in("✅", "5")
        .code("(c => c | @lt)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@lt","status":0,"input":5,"expected":["-1","0","1","null"]}')
    end

    it "the @OP.compare step bubbles its own error on mixed types" do
      expect_pipe
        .in("✅", '[1,"a"]')
        .code("(p => p | @OP.compare | @lt)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@OP.compare","status":0,"input":[1,"a"],"expected":["[_ ? @Number, _ ? @Number]","[_ ? @String, _ ? @String]"]}')
    end
  end

  describe "@filter" do
    it "keeps array elements where the predicate is truthy" do
      expect_pipe
        .in("✅", "[-1,2,-3,4]")
        .code('(xs => {"f": (n => [n, 0] | @OP.compare | @gt), "c": xs} | @filter)')
        .out("✅", "[2,4]")
    end

    it "keeps object values where the predicate is truthy, dropping keys" do
      expect_pipe
        .in("✅", '{"a":1,"b":3,"c":5}')
        .code('(o => {"f": (n => [n, 2] | @OP.compare | @gt), "c": o} | @filter)')
        .out("✅", '{"b":3,"c":5}')
    end

    it "is empty for the empty array" do
      expect_pipe
        .in("✅", "[]")
        .code('(xs => {"f": (n => n), "c": xs} | @filter)')
        .out("✅", "[]")
    end

    it "validates f eagerly on an empty collection" do
      expect_pipe
        .in("✅", "[]")
        .code('(xs => {"f": 5, "c": xs} | @filter)')
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@filter","status":0,"input":{"f":5,"c":[]},"expected":["{\"f\": _ ? @Function, \"c\": _ ? @Array}","{\"f\": _ ? @Function, \"c\": _ ? @Object}"]}')
    end

    it "errors on a non-{f,c} value" do
      expect_pipe
        .in("✅", "5")
        .code("(x => x | @filter)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@filter","status":0,"input":5,"expected":["{\"f\": _ ? @Function, \"c\": _ ? @Array}","{\"f\": _ ? @Function, \"c\": _ ? @Object}"]}')
    end
  end

  describe "@reduce" do
    it "combines the first two elements, then folds left with no seed" do
      expect_pipe
        .in("✅", "[1,2,3,4]")
        .code('(xs => {"f": @OP.sum, "c": xs} | @reduce)')
        .out("✅", "10")
    end

    it "returns the sole element of a single-element array unchanged" do
      expect_pipe
        .in("✅", "[42]")
        .code('(xs => {"f": @OP.sum, "c": xs} | @reduce)')
        .out("✅", "42")
    end

    it "threads the accumulator (order-sensitive)" do
      expect_pipe
        .in("✅", '["a","b","c"]')
        .code('(xs => {"f": @concat, "c": xs} | @reduce)')
        .out("✅", '"abc"')
    end

    it "errors on an empty array (no seed to fall back on)" do
      expect_pipe
        .in("✅", "[]")
        .code('(xs => {"f": @OP.sum, "c": xs} | @reduce)')
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@reduce","status":0,"input":{"f":"<function>","c":[]},"expected":["{\"f\": _ ? @Function, \"c\": [_, ...]}"]}')
    end

    it "errors on a non-{f,c} value" do
      expect_pipe
        .in("✅", "5")
        .code("(x => x | @reduce)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@reduce","status":0,"input":5,"expected":["{\"f\": _ ? @Function, \"c\": [_, ...]}"]}')
    end
  end

  describe "@compact" do
    it "drops null elements" do
      expect_pipe
        .in("✅", "[1,null,2,null,3]")
        .code("(xs => xs | @compact)")
        .out("✅", "[1,2,3]")
    end

    it "keeps a falsey non-null element like false or 0" do
      expect_pipe
        .in("✅", "[0,false,null,1]")
        .code("(xs => xs | @compact)")
        .out("✅", "[0,false,1]")
    end

    # Polymorphic like @filter: an object drops entries whose value is null,
    # keeping the surviving keys.
    it "drops null values from an object, keeping the keys" do
      expect_pipe
        .in("✅", '{"a":1,"b":null,"c":3}')
        .code("(o => o | @compact)")
        .out("✅", '{"a":1,"c":3}')
    end

    it "keeps a falsey non-null value in an object like false or 0" do
      expect_pipe
        .in("✅", '{"a":0,"b":false,"c":null,"d":1}')
        .code("(o => o | @compact)")
        .out("✅", '{"a":0,"b":false,"d":1}')
    end

    it "errors on a non-collection" do
      expect_pipe
        .in("✅", "5")
        .code("(x => x | @compact)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@compact","status":0,"input":5,"expected":["_ ? @Array","_ ? @Object"]}')
    end
  end

  describe "@flatten" do
    it "recursively flattens nested arrays" do
      expect_pipe
        .in("✅", "[1,[2,[3,4]],5]")
        .code("(xs => xs | @flatten)")
        .out("✅", "[1,2,3,4,5]")
    end

    it "leaves an already-flat array unchanged" do
      expect_pipe
        .in("✅", "[1,2,3]")
        .code("(xs => xs | @flatten)")
        .out("✅", "[1,2,3]")
    end

    it "is empty for the empty array" do
      expect_pipe
        .in("✅", "[]")
        .code("(xs => xs | @flatten)")
        .out("✅", "[]")
    end

    it "errors on a non-array" do
      expect_pipe
        .in("✅", "5")
        .code("(x => x | @flatten)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@flatten","status":0,"input":5,"expected":["_ ? @Array"]}')
    end
  end

  describe "@any" do
    it "is true when some element satisfies the predicate" do
      expect_pipe
        .in("✅", "[1,2,-3]")
        .code('(xs => {"f": (n => [n, 0] | @OP.compare | @lt), "c": xs} | @any)')
        .out("✅", "true")
    end

    it "is false when none satisfy it" do
      expect_pipe
        .in("✅", "[1,2,3]")
        .code('(xs => {"f": (n => [n, 0] | @OP.compare | @lt), "c": xs} | @any)')
        .out("✅", "false")
    end

    it "is false for the empty array" do
      expect_pipe
        .in("✅", "[]")
        .code('(xs => {"f": (n => n), "c": xs} | @any)')
        .out("✅", "false")
    end

    # Short-circuits: once an element is truthy, later elements are never tested,
    # so a predicate that would error on the second element is never reached.
    it "stops at the first truthy element without testing the rest" do
      expect_pipe
        .in("✅", "[true, false]")
        .code('(xs => {"f": (true => true, _ => [1, "x"] | @OP.compare), "c": xs} | @any)')
        .out("✅", "true")
    end

    # Like @map/@filter, @any is polymorphic on c: an object is tested by its values.
    it "is true when some object value satisfies the predicate" do
      expect_pipe
        .in("✅", '{"a":1,"b":-3}')
        .code('(o => {"f": (n => [n, 0] | @OP.compare | @lt), "c": o} | @any)')
        .out("✅", "true")
    end

    it "is false when no object value satisfies it" do
      expect_pipe
        .in("✅", '{"a":1,"b":2}')
        .code('(o => {"f": (n => [n, 0] | @OP.compare | @lt), "c": o} | @any)')
        .out("✅", "false")
    end

    it "is false for the empty object" do
      expect_pipe
        .in("✅", "{}")
        .code('(o => {"f": (n => n), "c": o} | @any)')
        .out("✅", "false")
    end

    it "errors on a non-{f,c} value" do
      expect_pipe
        .in("✅", "5")
        .code("(x => x | @any)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@any","status":0,"input":5,"expected":["{\"f\": _ ? @Function, \"c\": _ ? @Array}","{\"f\": _ ? @Function, \"c\": _ ? @Object}"]}')
    end
  end

  # @truthy / @falsey judge truthiness through @OP.not (false and null are falsey,
  # everything else truthy), so 0 and "" are truthy.
  describe "@truthy" do
    it "is true for a non-false, non-null value like 0" do
      expect_pipe
        .in("✅", "0")
        .code("(v => v | @truthy)")
        .out("✅", "true")
    end

    it "is false for false" do
      expect_pipe
        .in("✅", "false")
        .code("(v => v | @truthy)")
        .out("✅", "false")
    end

    it "is false for null" do
      expect_pipe
        .in("✅", "null")
        .code("(v => v | @truthy)")
        .out("✅", "false")
    end
  end

  describe "@falsey" do
    it "is true for null" do
      expect_pipe
        .in("✅", "null")
        .code("(v => v | @falsey)")
        .out("✅", "true")
    end

    it "is false for a truthy value like an empty string" do
      expect_pipe
        .in("✅", '""')
        .code("(v => v | @falsey)")
        .out("✅", "false")
    end
  end
end
