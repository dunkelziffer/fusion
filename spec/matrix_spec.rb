# frozen_string_literal: true

# The stdlib matrix module (stdlib/matrix): `@matrix/OP` reskins the operators
# for matrices, built on the named helpers `@matrix/multiply`, `@matrix/determinant`,
# `@matrix/scale`, `@matrix/rotate` and the `@matrix/Matrix` predicate. A matrix is
# a non-empty array of equal-length, non-empty rows of numbers.
#
# The module's own files resolve `@OP` to the sibling matrix OP.fsn, so their
# scalar arithmetic goes through the stable `@@OP` — these specs also pin that
# the reskin works end-to-end through the infix sugar (fixtures ref/matrixop).
RSpec.describe "stdlib matrix module", mutant_expression: "Fusion::CLI*" do
  describe "@matrix/Matrix" do
    it "is true for a rectangular matrix" do
      expect_pipe
        .in("✅", "[[1,2],[3,4]]")
        .code("(m => m | @matrix/Matrix)")
        .out("✅", "true")
    end

    it "is false for ragged rows" do
      expect_pipe
        .in("✅", "[[1],[2,3]]")
        .code("(m => m | @matrix/Matrix)")
        .out("✅", "false")
    end

    it "is false for a non-number entry" do
      expect_pipe
        .in("✅", '[[1,"x"]]')
        .code("(m => m | @matrix/Matrix)")
        .out("✅", "false")
    end

    it "is false for the empty array and empty rows" do
      expect_pipe
        .in("✅", "[[], []]")
        .code("(m => [m | @matrix/Matrix, [] | @matrix/Matrix])")
        .out("✅", "[false,false]")
    end

    it "is false for a non-array" do
      expect_pipe
        .in("✅", "5")
        .code("(m => m | @matrix/Matrix)")
        .out("✅", "false")
    end
  end

  describe "@matrix/multiply" do
    it "multiplies two square matrices" do
      expect_pipe
        .in("✅", "[[[1,2],[3,4]], [[5,6],[7,8]]]")
        .code("(p => p | @matrix/multiply)")
        .out("✅", "[[19,22],[43,50]]")
    end

    it "multiplies rectangular matrices with compatible dimensions" do
      expect_pipe
        .in("✅", "[[[1,2,3],[4,5,6]], [[7,8],[9,10],[11,12]]]")
        .code("(p => p | @matrix/multiply)")
        .out("✅", "[[58,64],[139,154]]")
    end

    it "is the identity when multiplying by the unit matrix" do
      expect_pipe
        .in("✅", "[[[1,2],[3,4]], [[1,0],[0,1]]]")
        .code("(p => p | @matrix/multiply)")
        .out("✅", "[[1,2],[3,4]]")
    end

    it "errors on a dimension mismatch" do
      expect_pipe
        .in("✅", "[[[1,2]], [[1,2]]]")
        .code("(p => p | @matrix/multiply)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@matrix/multiply","status":0,"input":[[[1,2]],[[1,2]]],"expected":["_ ? ([x ? @matrix/Matrix, y ? @matrix/Matrix] => (x | @matrix/dimensions)[1] == (y | @matrix/dimensions)[0])"]}')
    end

    it "errors on a non-matrix input" do
      expect_pipe
        .in("✅", "5")
        .code("(p => p | @matrix/multiply)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@matrix/multiply","status":0,"input":5,"expected":["_ ? ([x ? @matrix/Matrix, y ? @matrix/Matrix] => (x | @matrix/dimensions)[1] == (y | @matrix/dimensions)[0])"]}')
    end
  end

  describe "@matrix/determinant" do
    it "is the sole entry of a 1x1 matrix" do
      expect_pipe
        .in("✅", "[[5]]")
        .code("(m => m | @matrix/determinant)")
        .out("✅", "5")
    end

    it "computes a 2x2 determinant" do
      expect_pipe
        .in("✅", "[[1,2],[3,4]]")
        .code("(m => m | @matrix/determinant)")
        .out("✅", "-2")
    end

    it "computes a 3x3 determinant by Laplace expansion" do
      expect_pipe
        .in("✅", "[[6,1,1],[4,-2,5],[2,8,7]]")
        .code("(m => m | @matrix/determinant)")
        .out("✅", "-306")
    end

    it "errors on a non-square matrix" do
      expect_pipe
        .in("✅", "[[1,2,3],[4,5,6]]")
        .code("(m => m | @matrix/determinant)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@matrix/determinant","status":0,"input":[[1,2,3],[4,5,6]],"expected":["_ ? (sq ? @matrix/Matrix => sq | @matrix/dimensions | @OP.equal)"]}')
    end
  end

  describe "@matrix/scale" do
    it "scales elementwise by a number (scalar first)" do
      expect_pipe
        .in("✅", "[2, [[1,2],[3,4]]]")
        .code("(p => p | @matrix/scale)")
        .out("✅", "[[2,4],[6,8]]")
    end

    it "errors when the pair is not [number, matrix]" do
      expect_pipe
        .in("✅", "[[[1,2],[3,4]], 2]")
        .code("(p => p | @matrix/scale)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@matrix/scale","status":0,"input":[[[1,2],[3,4]],2],"expected":["[_ ? @Number, _ ? @matrix/Matrix]"]}')
    end
  end

  # @matrix/rotate multiplies the rotation matrix [[cos, -sin], [sin, cos]]
  # onto a 2x2 matrix. sin/cos results are libm floats, so the angle specs
  # round the entries rather than pinning machine-dependent digits.
  describe "@matrix/rotate" do
    it "keeps the matrix (as floats) at angle 0" do
      expect_pipe
        .in("✅", "[0, [[1,2],[3,4]]]")
        .code("(p => p | @matrix/rotate)")
        .out("✅", "[[1.0,2.0],[3.0,4.0]]")
    end

    it "rotates the unit matrix a quarter turn at pi/2" do
      expect_pipe
        .in("✅", "[[1,0],[0,1]]")
        .code("(m => [[@math.pi, 2] | @math.divide, m] | @matrix/rotate |: (row => row |: @math.round))")
        .out("✅", "[[0,-1],[1,0]]")
    end

    it "rotates the unit matrix a half turn at pi" do
      expect_pipe
        .in("✅", "[[1,0],[0,1]]")
        .code("(m => [@math.pi, m] | @matrix/rotate |: (row => row |: @math.round))")
        .out("✅", "[[-1,0],[0,-1]]")
    end

    it "errors on a matrix that is not 2x2" do
      expect_pipe
        .in("✅", "[1, [[1,2,3],[4,5,6]]]")
        .code("(p => p | @matrix/rotate)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@matrix/rotate","status":0,"input":[1,[[1,2,3],[4,5,6]]],"expected":["[_ ? @Number, [[_ ? @Number, _ ? @Number], [_ ? @Number, _ ? @Number]]]"]}')
    end

    it "errors when the angle does not come first" do
      expect_pipe
        .in("✅", "[[[1,2],[3,4]], 1]")
        .code("(p => p | @matrix/rotate)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@matrix/rotate","status":0,"input":[[[1,2],[3,4]],1],"expected":["[_ ? @Number, [[_ ? @Number, _ ? @Number], [_ ? @Number, _ ? @Number]]]"]}')
    end
  end

  # @matrix/column and @matrix/row extract a single line of a matrix as a plain
  # vector. The index is 0-based and strict: no negative or out-of-range access.
  describe "@matrix/column" do
    it "extracts the i-th column as a vector" do
      expect_pipe
        .in("✅", "[[[1,2],[3,4]], 1]")
        .code("(p => p | @matrix/column)")
        .out("✅", "[2,4]")
    end

    it "errors on an out-of-range index" do
      expect_pipe
        .in("✅", "[[[1,2],[3,4]], 2]")
        .code("(p => p | @matrix/column)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@matrix/column","status":0,"input":[[[1,2],[3,4]],2],"expected":["_ ? ([m ? @matrix/Matrix, i ? @Integer] => i >= 0 && i < m[0] | @size)"]}')
    end

    it "errors on a negative index (0-based, strict)" do
      expect_pipe
        .in("✅", "[[[1,2],[3,4]], -1]")
        .code("(p => p | @matrix/column)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@matrix/column","status":0,"input":[[[1,2],[3,4]],-1],"expected":["_ ? ([m ? @matrix/Matrix, i ? @Integer] => i >= 0 && i < m[0] | @size)"]}')
    end
  end

  describe "@matrix/row" do
    it "extracts the i-th row as a vector" do
      expect_pipe
        .in("✅", "[[[1,2],[3,4]], 1]")
        .code("(p => p | @matrix/row)")
        .out("✅", "[3,4]")
    end

    it "errors on an out-of-range index" do
      expect_pipe
        .in("✅", "[[[1,2],[3,4]], 2]")
        .code("(p => p | @matrix/row)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@matrix/row","status":0,"input":[[[1,2],[3,4]],2],"expected":["_ ? ([m ? @matrix/Matrix, i ? @Integer] => i >= 0 && i < m | @size)"]}')
    end
  end

  describe "@matrix/transpose" do
    it "turns columns into rows" do
      expect_pipe
        .in("✅", "[[1,2,3],[4,5,6]]")
        .code("(m => m | @matrix/transpose)")
        .out("✅", "[[1,4],[2,5],[3,6]]")
    end

    it "is an involution on a square matrix" do
      expect_pipe
        .in("✅", "[[1,2],[3,4]]")
        .code("(m => m | @matrix/transpose | @matrix/transpose)")
        .out("✅", "[[1,2],[3,4]]")
    end

    it "errors on a non-matrix" do
      expect_pipe
        .in("✅", "5")
        .code("(m => m | @matrix/transpose)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@matrix/transpose","status":0,"input":5,"expected":["_ ? @matrix/Matrix"]}')
    end
  end

  describe "@matrix/dimensions" do
    it "reports the dimensions as [rows, columns]" do
      expect_pipe
        .in("✅", "[[1,2,3],[4,5,6]]")
        .code("(m => m | @matrix/dimensions)")
        .out("✅", "[2,3]")
    end

    it "errors on a non-matrix" do
      expect_pipe
        .in("✅", "5")
        .code("(m => m | @matrix/dimensions)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@matrix/dimensions","status":0,"input":5,"expected":["_ ? @matrix/Matrix"]}')
    end
  end

  describe "@matrix/minor" do
    it "drops row r and column c" do
      expect_pipe
        .in("✅", "[[[1,2,3],[4,5,6],[7,8,9]], 1, 1]")
        .code("(p => p | @matrix/minor)")
        .out("✅", "[[1,3],[7,9]]")
    end

    it "errors when the matrix is smaller than 2 by 2" do
      expect_pipe
        .in("✅", "[[[5]], 0, 0]")
        .code("(p => p | @matrix/minor)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@matrix/minor","status":0,"input":[[[5]],0,0],"expected":["_ ? ([m ? @matrix/Matrix, r ? @Integer, c ? @Integer] => r >= 0 && r < m | @size && c >= 0 && c < m[0] | @size && m | @size >= 2 && m[0] | @size >= 2)"]}')
    end
  end

  describe "@matrix/subtract" do
    it "subtracts the second matrix from the first" do
      expect_pipe
        .in("✅", "[[[5,6],[7,8]], [[1,2],[3,4]]]")
        .code("(p => p | @matrix/subtract)")
        .out("✅", "[[4,4],[4,4]]")
    end

    it "errors on differently sized matrices" do
      expect_pipe
        .in("✅", "[[[1,2]], [[1,2],[3,4]]]")
        .code("(p => p | @matrix/subtract)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@matrix/subtract","status":0,"input":[[[1,2]],[[1,2],[3,4]]],"expected":["_ ? ([a ? @matrix/Matrix, b ? @matrix/Matrix] => [a, b] |: @matrix/dimensions | @OP.equal)"]}')
    end
  end

  describe "@matrix/identity" do
    it "builds the n-by-n identity matrix" do
      expect_pipe
        .in("✅", "3")
        .code("(n => n | @matrix/identity)")
        .out("✅", "[[1,0,0],[0,1,0],[0,0,1]]")
    end

    it "leaves a matrix unchanged under multiplication" do
      expect_pipe
        .in("✅", "[[1,2],[3,4]]")
        .code("(m => [m, 2 | @matrix/identity] | @matrix/multiply)")
        .out("✅", "[[1,2],[3,4]]")
    end

    it "errors on a non-positive size" do
      expect_pipe
        .in("✅", "0")
        .code("(n => n | @matrix/identity)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@matrix/identity","status":0,"input":0,"expected":["_ ? (n ? @Integer => n > 0)"]}')
    end
  end

  describe "@matrix/add" do
    it "adds two matrices elementwise" do
      expect_pipe
        .in("✅", "[[[1,2],[3,4]], [[5,6],[7,8]]]")
        .code("(p => p | @matrix/add)")
        .out("✅", "[[6,8],[10,12]]")
    end

    it "errors on differently sized matrices" do
      expect_pipe
        .in("✅", "[[[1,2]], [[1,2],[3,4]]]")
        .code("(p => p | @matrix/add)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@matrix/add","status":0,"input":[[[1,2]],[[1,2],[3,4]]],"expected":["_ ? ([a ? @matrix/Matrix, b ? @matrix/Matrix] => [a, b] |: @matrix/dimensions | @OP.equal)"]}')
    end

    it "errors on a non-matrix operand" do
      expect_pipe
        .in("✅", "[[[1,2],[3,4]], 5]")
        .code("(p => p | @matrix/add)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@matrix/add","status":0,"input":[[[1,2],[3,4]],5],"expected":["_ ? ([a ? @matrix/Matrix, b ? @matrix/Matrix] => [a, b] |: @matrix/dimensions | @OP.equal)"]}')
    end
  end

  describe "@matrix/OP members" do
    it "sums matrices elementwise, n-ary" do
      expect_pipe
        .in("✅", "[[[1,2],[3,4]], [[5,6],[7,8]], [[1,1],[1,1]]]")
        .code("(ms => ms | @matrix/OP.sum)")
        .out("✅", "[[7,9],[11,13]]")
    end

    it "rejects a sum of differently sized matrices" do
      expect_pipe
        .in("✅", "[[[1,2]], [[1,2],[3,4]]]")
        .code("(ms => ms | @matrix/OP.sum)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@matrix/sum","status":0,"input":[[[1,2]],[[1,2],[3,4]]],"expected":["_ ? (ms => [ms | @Array, ms | @size > 0, {\"c\": ms, \"f\": @matrix/Matrix} | @all, ms |: @matrix/dimensions | @OP.equal] | @OP.and | @safe)"]}')
    end

    # The guard is a flat conditions array ending in @OP.and | @safe: a condition
    # that errors makes the guard false, so every bad input gets @matrix/sum's
    # own error — no inner helper's error leaks through.
    it "rejects a non-matrix element with sum's own error" do
      expect_pipe
        .in("✅", "[5]")
        .code("(ms => ms | @matrix/OP.sum)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@matrix/sum","status":0,"input":[5],"expected":["_ ? (ms => [ms | @Array, ms | @size > 0, {\"c\": ms, \"f\": @matrix/Matrix} | @all, ms |: @matrix/dimensions | @OP.equal] | @OP.and | @safe)"]}')
    end

    it "rejects the empty array with sum's own error" do
      expect_pipe
        .in("✅", "[]")
        .code("(ms => ms | @matrix/OP.sum)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@matrix/sum","status":0,"input":[],"expected":["_ ? (ms => [ms | @Array, ms | @size > 0, {\"c\": ms, \"f\": @matrix/Matrix} | @all, ms |: @matrix/dimensions | @OP.equal] | @OP.and | @safe)"]}')
    end

    it "rejects a non-array with sum's own error" do
      expect_pipe
        .in("✅", "5")
        .code("(ms => ms | @matrix/OP.sum)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@matrix/sum","status":0,"input":5,"expected":["_ ? (ms => [ms | @Array, ms | @size > 0, {\"c\": ms, \"f\": @matrix/Matrix} | @all, ms |: @matrix/dimensions | @OP.equal] | @OP.and | @safe)"]}')
    end

    it "negates elementwise" do
      expect_pipe
        .in("✅", "[[1,2],[3,4]]")
        .code("(m => m | @matrix/OP.negate)")
        .out("✅", "[[-1,-2],[-3,-4]]")
    end

    it "folds a product chain through @matrix/multiply" do
      expect_pipe
        .in("✅", "[[[1,2],[3,4]], [[5,6],[7,8]]]")
        .code("(ms => ms | @matrix/OP.product)")
        .out("✅", "[[19,22],[43,50]]")
    end

    # The guard is a flat conditions array ending in @OP.and | @safe, so a bad
    # shape gets @matrix/product's own error. A dimension mismatch is the one
    # documented exception: it surfaces as @matrix/multiply's error from the fold.
    it "rejects a non-matrix element with product's own error" do
      expect_pipe
        .in("✅", "[5]")
        .code("(ms => ms | @matrix/OP.product)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@matrix/product","status":0,"input":[5],"expected":["_ ? (ms => [ms | @Array, ms | @size > 0, {\"c\": ms, \"f\": @matrix/Matrix} | @all] | @OP.and | @safe)"]}')
    end

    it "rejects the empty array with product's own error" do
      expect_pipe
        .in("✅", "[]")
        .code("(ms => ms | @matrix/OP.product)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@matrix/product","status":0,"input":[],"expected":["_ ? (ms => [ms | @Array, ms | @size > 0, {\"c\": ms, \"f\": @matrix/Matrix} | @all] | @OP.and | @safe)"]}')
    end

    it "rejects a non-array with product's own error" do
      expect_pipe
        .in("✅", "5")
        .code("(ms => ms | @matrix/OP.product)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@matrix/product","status":0,"input":5,"expected":["_ ? (ms => [ms | @Array, ms | @size > 0, {\"c\": ms, \"f\": @matrix/Matrix} | @all] | @OP.and | @safe)"]}')
    end

    it "surfaces a dimension mismatch as @matrix/multiply's error" do
      expect_pipe
        .in("✅", "[[[1,2]], [[1,2]]]")
        .code("(ms => ms | @matrix/OP.product)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@matrix/multiply","status":0,"input":[[[1,2]],[[1,2]]],"expected":["_ ? ([x ? @matrix/Matrix, y ? @matrix/Matrix] => (x | @matrix/dimensions)[1] == (y | @matrix/dimensions)[0])"]}')
    end

    it "inverts an invertible matrix (always floats)" do
      expect_pipe
        .in("✅", "[[1,2],[3,4]]")
        .code("(m => m | @matrix/OP.invert)")
        .out("✅", "[[-2.0,1.0],[1.5,-0.5]]")
    end

    it "yields the identity for matrix times inverse" do
      expect_pipe
        .in("✅", "[[2,0],[0,4]]")
        .code("(m => [m, m | @matrix/OP.invert] | @matrix/multiply)")
        .out("✅", "[[1.0,0.0],[0.0,1.0]]")
    end

    it "raises math_error on a singular matrix" do
      expect_pipe
        .in("✅", "[[1,2],[2,4]]")
        .code("(m => m | @matrix/OP.invert)")
        .out("❌", '{"kind":"math_error","origin":"stdlib","file":"<inline>","operation":"@matrix/invert","status":0,"input":[[1,2],[2,4]],"message":"singular matrix (determinant 0)"}')
    end

    it "always raises on quotient" do
      expect_pipe
        .in("✅", "[[[1,2],[3,4]], [[5,6],[7,8]]]")
        .code("(p => p | @matrix/OP.quotient)")
        .out("❌", '{"kind":"math_error","origin":"stdlib","file":"<inline>","operation":"@matrix/OP.quotient","status":0,"input":[[[1,2],[3,4]],[[5,6],[7,8]]],"message":"integer division is not defined for matrices"}')
    end

    it "always raises on modulo" do
      expect_pipe
        .in("✅", "[[[1,2],[3,4]], [[5,6],[7,8]]]")
        .code("(p => p | @matrix/OP.modulo)")
        .out("❌", '{"kind":"math_error","origin":"stdlib","file":"<inline>","operation":"@matrix/OP.modulo","status":0,"input":[[[1,2],[3,4]],[[5,6],[7,8]]],"message":"modulo is not defined for matrices"}')
    end

    it "keeps the untouched members at their builtin meaning (equal via the spread)" do
      expect_pipe
        .in("✅", "[[[1,2],[3,4]], [[1,2],[3,4]]]")
        .code("(p => p | @matrix/OP.equal)")
        .out("✅", "true")
    end
  end

  # A directory reskins its operators by pointing its OP.fsn at @matrix/OP
  # (fixtures ref/matrixop); the infix sugar then computes with matrices.
  describe "the reskin through the infix sugar" do
    it "computes a + b, a - b, a * b, and -a on matrices" do
      expect_pipe
        .in("✅", "[[[1,2],[3,4]], [[5,6],[7,8]]]")
        .file_path("ref/matrixop/calc.fsn")
        .out("✅", "[[[6,8],[10,12]],[[-4,-4],[-4,-4]],[[19,22],[43,50]],[[-1,-2],[-3,-4]]]")
    end

    it "computes a / b as multiplication by the inverse" do
      expect_pipe
        .in("✅", "[[[1,2],[3,4]], [[5,6],[7,8]]]")
        .file_path("ref/matrixop/divide.fsn")
        .out("✅", "[[3.0,-2.0],[2.0,-1.0]]")
    end

    it "raises on % with the user file as the call site" do
      expect_pipe
        .in("✅", "[[[1,2],[3,4]], [[5,6],[7,8]]]")
        .file_path("ref/matrixop/modulo.fsn")
        .out("❌", '{"kind":"math_error","origin":"stdlib","file":"spec/fixtures/ref/matrixop/modulo.fsn","operation":"@matrix/OP.modulo","status":0,"input":[[[1,2],[3,4]],[[5,6],[7,8]]],"message":"modulo is not defined for matrices"}')
    end
  end
end
