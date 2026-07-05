# frozen_string_literal: true

# Operator syntax sugar (reference §2.7). Every operator desugars to a
# pipe into an `@OP.*` member (or a stdlib call for the map-pipes).
# These specs drive the real behavior through the pipe, using the
# sugar exclusively — the sugar-free forms are covered by the other specs.
#
# Where a precedence/associativity claim is made, the input is chosen so the
# *opposite* rule would produce a different (noted) result — otherwise the test
# would not actually pin the rule down.
RSpec.describe "syntax sugar" do
  describe "arithmetic and its precedence" do
    it "adds a pair" do
      expect_pipe
        .code("(_ => 2 + 3)")
        .out("✅", "5")
    end

    it "sums a run of operands" do
      expect_pipe
        .code("(_ => 1 + 2 + 3 + 4)")
        .out("✅", "10")
    end

    it "subtracts left-to-right (10 - 3 - 2 is 5, not 9)" do
      expect_pipe
        .code("(_ => 10 - 3 - 2)")
        .out("✅", "5")
    end

    it "parses + followed by a unary - (a + -b)" do
      expect_pipe
        .in("✅", "5")
        .code("(x => x + -x)")
        .out("✅", "0")
    end

    it "evaluates a mixed +/- run with the right signs" do
      expect_pipe
        .code("(_ => 1 + 2 - 42 + 10 - 3)")
        .out("✅", "-32")
    end

    it "double-negates a negated term (2 - -3 is 5, not -1)" do
      expect_pipe
        .code("(_ => 2 - -3)")
        .out("✅", "5")
    end

    it "multiplies a run of operands" do
      expect_pipe
        .code("(_ => 2 * 3 * 4)")
        .out("✅", "24")
    end

    it "divides via reciprocal (always a float, so 12 / 4 is 3.0 not 3)" do
      expect_pipe
        .code("(_ => 12 / 4)")
        .out("✅", "3.0")
    end

    it "divides left-to-right (100 / 2 / 5 is 10.0, not 250.0)" do
      expect_pipe
        .code("(_ => 100 / 2 / 5)")
        .out("✅", "10.0")
    end

    it "combines * and /" do
      expect_pipe
        .code("(_ => 2 * 3 / 4)")
        .out("✅", "1.5")
    end

    it "parses * followed by a unary / (a * /b)" do
      expect_pipe
        .in("✅", "4")
        .code("(x => x * /x)")
        .out("✅", "1.0")
    end

    it "applies a unary - to a product operand (-5 * 2 is -10, not 10)" do
      expect_pipe
        .code("(_ => -5 * 2)")
        .out("✅", "-10")
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

    it "applies % after a product run, not before (3 * 4 % 5 is 2, not 12)" do
      expect_pipe
        .code("(_ => 3 * 4 % 5)")
        .out("✅", "2")
    end

    it "starts a fresh product run from a % result (17 % 5 * 2 is 4, not 7)" do
      expect_pipe
        .code("(_ => 17 % 5 * 2)")
        .out("✅", "4")
    end

    it "chains * and // left-associatively (7 * 10 // 3 is 23, not 21)" do
      expect_pipe
        .code("(_ => 7 * 10 // 3)")
        .out("✅", "23")
    end

    it "does not let // reassociate the product to its right (12 // 4 * 3 is 9, not 1)" do
      expect_pipe
        .code("(_ => 12 // 4 * 3)")
        .out("✅", "9")
    end

    it "chains // left-associatively (20 // 6 // 2 is 1, not 6)" do
      expect_pipe
        .code("(_ => 20 // 6 // 2)")
        .out("✅", "1")
    end

    it "interleaves *, %, // strictly left-to-right (2 * 3 % 4 * 5 is 10, not 30 or 6)" do
      expect_pipe
        .code("(_ => 2 * 3 % 4 * 5)")
        .out("✅", "10")
    end

    it "binds * tighter than + (2 + 3 * 4 is 14, not 20)" do
      expect_pipe
        .code("(_ => 2 + 3 * 4)")
        .out("✅", "14")
    end

    it "errors on / by zero at runtime (invert never folds to a literal)" do
      expect_pipe
        .code("(_ => 1 / 0)")
        .out("❌", '{"kind":"math_error","origin":"builtin","file":"<inline>","operation":"@OP.invert","status":0,"input":0,"message":"division by zero"}')
    end

    it "errors on % by zero" do
      expect_pipe
        .code("(_ => 5 % 0)")
        .out("❌", '{"kind":"math_error","origin":"builtin","file":"<inline>","operation":"@OP.modulo","status":0,"input":[5,0],"message":"modulo by zero"}')
    end

    it "errors on // by zero" do
      expect_pipe
        .code("(_ => 5 // 0)")
        .out("❌", '{"kind":"math_error","origin":"builtin","file":"<inline>","operation":"@OP.quotient","status":0,"input":[5,0],"message":"division by zero"}')
    end
  end

  describe "unary prefixes" do
    it "negates a binding via @OP.negate" do
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

    it "nots a truthy value (0 is truthy, so ~0 is false)" do
      expect_pipe
        .code("(_ => ~0)")
        .out("✅", "false")
    end

    it "nots a falsey value" do
      expect_pipe
        .code("(_ => ~null)")
        .out("✅", "true")
    end

    it "binds unary / tighter than * (/2 * 4 is 2.0, not 0.125)" do
      expect_pipe
        .code("(_ => /2 * 4)")
        .out("✅", "2.0")
    end

    it "binds unary / tighter than + (/4 + 1 is 1.25, not 0.2)" do
      expect_pipe
        .code("(_ => /4 + 1)")
        .out("✅", "1.25")
    end

    it "binds unary ~ tighter than && (~false && false is false, not true)" do
      expect_pipe
        .code("(_ => ~false && false)")
        .out("✅", "false")
    end

    it "folds a leading unary - into the surrounding sum (-x + 10 is 7, not -13)" do
      expect_pipe
        .in("✅", "3")
        .code("(x => -x + 10)")
        .out("✅", "7")
    end

    it "binds postfix .member tighter than unary - (-o.n reads then negates)" do
      expect_pipe
        .in("✅", '{"n":5}')
        .code("(o => -o.n)")
        .out("✅", "-5")
    end

    it "binds postfix [] tighter than unary - (-a[0] reads then negates)" do
      expect_pipe
        .in("✅", "[7,8]")
        .code("(a => -a[0])")
        .out("✅", "-7")
    end

    it "binds ! tighter than + (!5 + 3 is the error 5, not the error 8)" do
      expect_pipe
        .code("(_ => !5 + 3)")
        .out("❌", "5")
    end

    it "binds ! tighter than | (!5 is the piped value, caught as 5)" do
      expect_pipe
        .code("(_ => !5 | (!n => n))")
        .out("✅", "5")
    end
  end

  describe "comparison, ordering, and boolean precedence" do
    it "tests equality exactly (an int never equals a float)" do
      expect_pipe
        .code("(_ => 1 == 1.0)")
        .out("✅", "false")
    end

    it "compares deeply" do
      expect_pipe
        .code("(_ => [1, 2] == [1, 2])")
        .out("✅", "true")
    end

    it "folds == over all operands, not as left-assoc chaining (2 == 2 == 2 is true, not false)" do
      expect_pipe
        .code("(_ => 2 == 2 == 2)")
        .out("✅", "true")
    end

    it "orders a smaller-first pair as -1" do
      expect_pipe
        .code("(_ => 1 ?? 2)")
        .out("✅", "-1")
    end

    it "orders an equal pair as 0" do
      expect_pipe
        .code("(_ => 2 ?? 2)")
        .out("✅", "0")
    end

    it "orders a larger-first pair as 1" do
      expect_pipe
        .code("(_ => 3 ?? 2)")
        .out("✅", "1")
    end

    it "orders strings" do
      expect_pipe
        .in("✅", '"a"')
        .code('(s => s ?? "b")')
        .out("✅", "-1")
    end

    it "binds ?? tighter than == (else -1 == 1 would compare a boolean and error)" do
      expect_pipe
        .code("(_ => -1 == 1 ?? 2)")
        .out("✅", "true")
    end

    it "compares two ?? results with ==" do
      expect_pipe
        .code("(_ => 1 ?? 2 == 3 ?? 4)")
        .out("✅", "true")
    end

    it "folds == over several ?? results" do
      expect_pipe
        .code("(_ => -1 == 1 ?? 2 == -1)")
        .out("✅", "true")
    end

    it "binds + tighter than ?? on the left (10 + 1 ?? 5 is 1, not 9)" do
      expect_pipe
        .code("(_ => 10 + 1 ?? 5)")
        .out("✅", "1")
    end

    it "binds + tighter than ?? on the right (1 ?? 0 + 2 is -1, not 3)" do
      expect_pipe
        .code("(_ => 1 ?? 0 + 2)")
        .out("✅", "-1")
    end

    it "binds == tighter than && (1 == 1 && 1 == 1 is true; if && were tighter it would be false)" do
      expect_pipe
        .code("(_ => 1 == 1 && 1 == 1)")
        .out("✅", "true")
    end

    it "is false when any && operand is falsey" do
      expect_pipe
        .code("(_ => true && true && false)")
        .out("✅", "false")
    end

    it "binds && tighter than || (true || false && false is true, not false)" do
      expect_pipe
        .code("(_ => true || false && false)")
        .out("✅", "true")
    end

    it "reads < via the (a ?? b) | @lt helper idiom (1 < 2 via @gt is false)" do
      expect_pipe
        .code("(_ => (1 ?? 2) | @gt)")
        .out("✅", "false")
    end

    it "reads > via the (a ?? b) | @gt helper idiom (3 > 2 is true)" do
      expect_pipe
        .code("(_ => (3 ?? 2) | @gt)")
        .out("✅", "true")
    end
  end

  describe "pipe precedence (tightest binary, just under unary)" do
    it "binds a pipe tighter than + (2 + 10 | f is 22, not 24)" do
      expect_pipe
        .code("(_ => 2 + 10 | (n => n * 2))")
        .out("✅", "22")
    end

    it "pipes a parenthesized arithmetic result onward" do
      expect_pipe
        .code("(_ => (2 + 10) | (n => n * 2))")
        .out("✅", "24")
    end

    it "binds a pipe tighter than == (else the pipe RHS would be @size == 3)" do
      expect_pipe
        .code("(_ => [1, 2, 3] |: (x => x) | @size == 3)")
        .out("✅", "true")
    end

    it "binds a pipe tighter than && (else the pipe RHS would be @Integer && 3)" do
      expect_pipe
        .code("(_ => 5 | @Integer && 3 | @Integer)")
        .out("✅", "true")
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

    it "propagates an error raised by the mapped function" do
      expect_pipe
        .code("(_ => [1, 2, 3] |: (x => !x))")
        .out("❌", "1")
    end

    it "errors when |: gets a non-collection" do
      expect_pipe
        .code("(_ => 5 |: (x => x))")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@map","status":0,"input":{"c":5,"f":"<function>"},"expected":["{\"f\": _ ? @Function, \"c\": _ ? @Array}","{\"f\": _ ? @Function, \"c\": _ ? @Object}"]}')
    end

    it "filters an array with |?" do
      expect_pipe
        .code("(_ => [1, 2, 3, 4] |? (x => x % 2 == 0))")
        .out("✅", "[2,4]")
    end

    it "filters an object's values with |?" do
      expect_pipe
        .code('(_ => {"a": 1, "b": 9} |? (x => (x ?? 5) | @gt))')
        .out("✅", '{"b":9}')
    end

    it "errors when |? gets a non-collection" do
      expect_pipe
        .code("(_ => 5 |? (x => x))")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@filter","status":0,"input":{"c":5,"f":"<function>"},"expected":["{\"f\": _ ? @Function, \"c\": _ ? @Array}","{\"f\": _ ? @Function, \"c\": _ ? @Object}"]}')
    end

    it "reduces an array with |+" do
      expect_pipe
        .code("(_ => [1, 2, 3, 4] |+ (p => p | ([a, b] => a + b)))")
        .out("✅", "10")
    end

    it "errors when |+ gets an empty array" do
      expect_pipe
        .code("(_ => [] |+ (p => p))")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@reduce","status":0,"input":{"c":[],"f":"<function>"},"expected":["{\"f\": _ ? @Function, \"c\": [_, ...]}"]}')
    end

    it "chains pipe-family operators left-associatively" do
      expect_pipe
        .code("(_ => [1, 2, 3] |: (x => x * 2) |? (x => x ?? 4 == -1))")
        .out("✅", "[2]")
    end

    it "mixes |: and | at the same (pipe) level, left-associatively" do
      expect_pipe
        .code("(_ => [1, 2] |: (x => x + 1) | (a => a))")
        .out("✅", "[2,3]")
    end
  end

  describe "negative literals" do
    it "keeps a literal array of negatives" do
      expect_pipe
        .code("(_ => [-1, -2, -3])")
        .out("✅", "[-1,-2,-3]")
    end

    it "keeps a negative object value" do
      expect_pipe
        .code('(_ => {"x": -5})')
        .out("✅", '{"x":-5}')
    end

    it "folds -5 - 42 into two negative-literal terms" do
      expect_pipe
        .code("(_ => -5 - 42)")
        .out("✅", "-47")
    end

    it "subtracts without spaces (- is always the operator, so a-3 is subtraction)" do
      expect_pipe
        .in("✅", "10")
        .code("(a => a-3)")
        .out("✅", "7")
    end

    it "matches a bare negative literal pattern" do
      expect_pipe
        .in("✅", "-1")
        .code('(-1 => "neg one", _ => "other")')
        .out("✅", '"neg one"')
    end

    it "matches a negative literal inside an array pattern" do
      expect_pipe
        .in("✅", "[-1, 42]")
        .code("([-1, x] => x)")
        .out("✅", "42")
    end
  end

  describe "paths vs. division" do
    it "reads a tight @a/b as one file path" do
      expect_pipe
        .code("(_ => @foo/bar)")
        .out("❌", '{"kind":"reference_error","origin":"code","file":"<inline>","operation":"@foo/bar","status":0,"input":null,"message":"unresolved reference"}')
    end

    it "reads a tight multi-segment path @a/b/c" do
      expect_pipe
        .code("(_ => @foo/bar/baz)")
        .out("❌", '{"kind":"reference_error","origin":"code","file":"<inline>","operation":"@foo/bar/baz","status":0,"input":null,"message":"unresolved reference"}')
    end

    it "reads a spaced @a / b as division of @a" do
      expect_pipe
        .code("(_ => @foo / bar)")
        .out("❌", '{"kind":"reference_error","origin":"code","file":"<inline>","operation":"@foo","status":0,"input":null,"message":"unresolved reference"}')
    end

    it "treats @a / 3 as division (a number can't be a path segment)" do
      expect_pipe
        .code("(_ => @foo / 3)")
        .out("❌", '{"kind":"reference_error","origin":"code","file":"<inline>","operation":"@foo","status":0,"input":null,"message":"unresolved reference"}')
    end

    it "treats @a // b as an integer quotient, never a path" do
      expect_pipe
        .code("(_ => @foo // bar)")
        .out("❌", '{"kind":"reference_error","origin":"code","file":"<inline>","operation":"@foo","status":0,"input":null,"message":"unresolved reference"}')
    end

    it "reads an upward tight path @../x" do
      expect_pipe
        .code("(_ => @../x)")
        .out("❌", '{"kind":"reference_error","origin":"code","file":"<inline>","operation":"@../x","status":0,"input":null,"message":"outside the jail"}')
    end

    it "treats @.map as .map access on bare @ (a `.` never starts a path)" do
      expect_pipe
        .code("(_ => @.map)")
        .out("❌", '{"kind":"argument_error","origin":"code","file":"<inline>","operation":".map","status":0,"input":"<function>","expected":["_ ? @Object"]}')
    end

    it "rejects whitespace between @ and its path" do
      expect_pipe
        .code("(_ => @ foo)")
        .out("❌", a_string_including('"kind":"syntax_error"', '"origin":"code"', '"file":"<inline>"', '"operation":"parsing code"', '"status":0', '"message":'))
    end
  end
end
