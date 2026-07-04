# frozen_string_literal: true

# Operator syntax sugar (reference §2.7). Every operator desugars to a
# pipe into an `@OP.*` member (or a stdlib call for the map-pipes).
# These specs drive the real behavior through the pipe, using the
# sugar exclusively — the sugar-free forms are covered by the other specs.
RSpec.describe "syntax sugar" do
  describe "arithmetic" do
    it "adds a pair" do
      expect_pipe
        .code("(_ => 2 + 3)")
        .out("✅", "5")
    end

    it "folds a run of + into one sum" do
      expect_pipe
        .code("(_ => 1 + 2 + 3 + 4)")
        .out("✅", "10")
    end

    it "subtracts, negating the term" do
      expect_pipe
        .code("(_ => 10 - 3 - 2)")
        .out("✅", "5")
    end

    it "mixes + and - in one run" do
      expect_pipe
        .code("(_ => 1 + 2 - 3 + 4)")
        .out("✅", "4")
    end

    it "multiplies a run" do
      expect_pipe
        .code("(_ => 2 * 3 * 4)")
        .out("✅", "24")
    end

    it "divides via reciprocal (always a float)" do
      expect_pipe
        .code("(_ => 12 / 4)")
        .out("✅", "3.0")
    end

    it "mixes * and / in one product run" do
      expect_pipe
        .code("(_ => 2 * 3 / 4)")
        .out("✅", "1.5")
    end

    it "takes a modulo" do
      expect_pipe
        .code("(_ => 17 % 5)")
        .out("✅", "2")
    end

    it "takes an integer quotient" do
      expect_pipe
        .code("(_ => 17 // 5)")
        .out("✅", "3")
    end

    it "binds * tighter than +" do
      expect_pipe
        .code("(_ => 2 + 3 * 4)")
        .out("✅", "14")
    end

    it "chains % and // left-associatively with * (standard precedence)" do
      expect_pipe
        .code("(_ => 7 * 10 // 3)")
        .out("✅", "23")
    end

    it "chains // left-associatively" do
      expect_pipe
        .code("(_ => 20 // 6 // 2)")
        .out("✅", "1")
    end
  end

  describe "unary operators" do
    it "negates a non-literal via @OP.negate" do
      expect_pipe
        .in("✅", "5")
        .code("(x => -x)")
        .out("✅", "-5")
    end

    it "inverts with a leading /" do
      expect_pipe
        .in("✅", "4")
        .code("(x => /x)")
        .out("✅", "0.25")
    end

    it "logically nots a truthy value" do
      expect_pipe
        .code("(_ => ~0)")
        .out("✅", "false")
    end

    it "logically nots a falsey value" do
      expect_pipe
        .code("(_ => ~null)")
        .out("✅", "true")
    end
  end

  describe "comparison and logic" do
    it "tests equality" do
      expect_pipe
        .code("(_ => 2 == 3)")
        .out("✅", "false")
    end

    it "folds a run of == (all equal)" do
      expect_pipe
        .code("(_ => 2 == 2 == 2)")
        .out("✅", "true")
    end

    it "compares to an ordinal with ??" do
      expect_pipe
        .code("(_ => 1 ?? 2)")
        .out("✅", "-1")
    end

    it "binds ?? tighter than == (compare feeds into equality)" do
      expect_pipe
        .code("(_ => -1 == 1 ?? 2)")
        .out("✅", "true")
    end

    it "folds && n-ary" do
      expect_pipe
        .code("(_ => true && true && false)")
        .out("✅", "false")
    end

    it "binds && tighter than ||" do
      expect_pipe
        .code("(_ => false || true && false)")
        .out("✅", "false")
    end
  end

  describe "pipe precedence" do
    it "binds a pipe tighter than arithmetic" do
      expect_pipe
        .code("(_ => 2 + 10 | (n => n * 2))")
        .out("✅", "22")
    end

    it "pipes a parenthesized arithmetic result onward" do
      expect_pipe
        .code("(_ => (2 + 10) | (n => n * 2))")
        .out("✅", "24")
    end
  end

  describe "map / filter / reduce pipes" do
    it "maps an array with |:" do
      expect_pipe
        .code("(_ => [1, 2, 3] |: (x => x * 2))")
        .out("✅", "[2,4,6]")
    end

    it "maps an object's values with |:" do
      expect_pipe
        .code('(_ => {"a": 1, "b": 2} |: (x => x + 10))')
        .out("✅", '{"a":11,"b":12}')
    end

    it "filters an array with |?" do
      expect_pipe
        .code("(_ => [1, 2, 3, 4] |? (x => x % 2 == 0))")
        .out("✅", "[2,4]")
    end

    it "reduces an array with |+" do
      expect_pipe
        .code("(_ => [1, 2, 3, 4] |+ (p => p | ([a, b] => a + b)))")
        .out("✅", "10")
    end

    it "chains pipe-family operators left-associatively" do
      expect_pipe
        .code("(_ => [1, 2, 3] |: (x => x * 2) |? (x => x ?? 4 == -1))")
        .out("✅", "[2]")
    end
  end

  describe "negative literals" do
    it "keeps a literal array of negatives" do
      expect_pipe
        .code("(_ => [-1, -2, -3])")
        .out("✅", "[-1,-2,-3]")
    end

    it "folds -5 - 42 into two negative-literal terms" do
      expect_pipe
        .code("(_ => -5 - 42)")
        .out("✅", "-47")
    end

    it "subtracts without spaces (- is always the operator)" do
      expect_pipe
        .in("✅", "10")
        .code("(a => a-3)")
        .out("✅", "7")
    end

    it "matches a negative literal pattern" do
      expect_pipe
        .in("✅", "-1")
        .code('(-1 => "neg one", _ => "other")')
        .out("✅", '"neg one"')
    end
  end

  describe "paths vs. division" do
    it "reads a tight @a/b as one file path" do
      expect_pipe
        .code("(_ => @foo/bar)")
        .out("❌", '{"kind":"reference_error","origin":"code","file":"<inline>","operation":"@foo/bar","status":0,"input":null,"message":"unresolved reference"}')
    end

    it "reads a spaced @a / b as division of @a" do
      expect_pipe
        .code("(_ => @foo / bar)")
        .out("❌", '{"kind":"reference_error","origin":"code","file":"<inline>","operation":"@foo","status":0,"input":null,"message":"unresolved reference"}')
    end

    it "rejects whitespace between @ and its path" do
      expect_pipe
        .code("(_ => @ foo)")
        .out("❌", a_string_including(
          '"kind":"syntax_error"', '"origin":"code"', '"file":"<inline>"', '"operation":"parsing code"', '"status":0', '"message":'
        ))
    end
  end
end
