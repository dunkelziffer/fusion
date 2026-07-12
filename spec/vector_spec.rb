# frozen_string_literal: true

# The stdlib vector module (stdlib/vector): arithmetic over plain non-empty
# arrays of numbers, validated by the @vector/Vector predicate (@matrix/Matrix
# builds on it: a matrix is a non-empty array of equally sized vectors).
RSpec.describe "stdlib vector module", mutant_expression: "Fusion::CLI*" do
  describe "@vector/Vector" do
    it "is true for a non-empty array of numbers" do
      expect_pipe
        .in("✅", "[1,2.5,-3]")
        .code("(v => v | @vector/Vector)")
        .out("✅", "true")
    end

    it "is false for the empty array" do
      expect_pipe
        .in("✅", "[]")
        .code("(v => v | @vector/Vector)")
        .out("✅", "false")
    end

    it "is false for a non-number element" do
      expect_pipe
        .in("✅", '[1,"x"]')
        .code("(v => v | @vector/Vector)")
        .out("✅", "false")
    end

    it "is false for a non-array" do
      expect_pipe
        .in("✅", "5")
        .code("(v => v | @vector/Vector)")
        .out("✅", "false")
    end
  end

  describe "@vector/dot" do
    it "computes the dot product of two equal-length vectors" do
      expect_pipe
        .in("✅", "[[1,2,3],[4,5,6]]")
        .code("(p => p | @vector/dot)")
        .out("✅", "32")
    end

    it "handles two-dimensional vectors" do
      expect_pipe
        .in("✅", "[[1,2],[3,4]]")
        .code("(p => p | @vector/dot)")
        .out("✅", "11")
    end

    it "errors on a length mismatch" do
      expect_pipe
        .in("✅", "[[1,2],[3,4,5]]")
        .code("(p => p | @vector/dot)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@vector/dot","status":0,"input":[[1,2],[3,4,5]],"expected":["_ ? ([u ? @vector/Vector, v ? @vector/Vector] => [u, v] |: @size | @OP.equal)"]}')
    end

    it "errors on a non-number element" do
      expect_pipe
        .in("✅", '[[1,"x"],[3,4]]')
        .code("(p => p | @vector/dot)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@vector/dot","status":0,"input":[[1,"x"],[3,4]],"expected":["_ ? ([u ? @vector/Vector, v ? @vector/Vector] => [u, v] |: @size | @OP.equal)"]}')
    end
  end

  describe "@vector/add" do
    it "adds two equal-length vectors elementwise" do
      expect_pipe
        .in("✅", "[[1,2],[10,20]]")
        .code("(p => p | @vector/add)")
        .out("✅", "[11,22]")
    end

    it "errors on a length mismatch" do
      expect_pipe
        .in("✅", "[[1,2],[3,4,5]]")
        .code("(p => p | @vector/add)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@vector/add","status":0,"input":[[1,2],[3,4,5]],"expected":["_ ? ([u ? @vector/Vector, v ? @vector/Vector] => [u, v] |: @size | @OP.equal)"]}')
    end
  end

  describe "@vector/scale" do
    it "scales a vector elementwise by a number (scalar first)" do
      expect_pipe
        .in("✅", "[2, [1,2,3]]")
        .code("(p => p | @vector/scale)")
        .out("✅", "[2,4,6]")
    end

    it "errors when the scalar does not come first" do
      expect_pipe
        .in("✅", "[[1,2,3], 2]")
        .code("(p => p | @vector/scale)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@vector/scale","status":0,"input":[[1,2,3],2],"expected":["[_ ? @Number, _ ? @vector/Vector]"]}')
    end

    it "errors on the empty vector" do
      expect_pipe
        .in("✅", "[2, []]")
        .code("(p => p | @vector/scale)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@vector/scale","status":0,"input":[2,[]],"expected":["[_ ? @Number, _ ? @vector/Vector]"]}')
    end
  end

  describe "@vector/subtract" do
    it "subtracts the second vector from the first" do
      expect_pipe
        .in("✅", "[[5,7],[1,2]]")
        .code("(p => p | @vector/subtract)")
        .out("✅", "[4,5]")
    end

    it "errors on a length mismatch" do
      expect_pipe
        .in("✅", "[[1,2],[3,4,5]]")
        .code("(p => p | @vector/subtract)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@vector/subtract","status":0,"input":[[1,2],[3,4,5]],"expected":["_ ? ([u ? @vector/Vector, v ? @vector/Vector] => [u, v] |: @size | @OP.equal)"]}')
    end
  end

  describe "@vector/norm" do
    it "computes the Euclidean length, always a float" do
      expect_pipe
        .in("✅", "[3,4]")
        .code("(v => v | @vector/norm)")
        .out("✅", "5.0")
    end

    it "errors on a non-vector" do
      expect_pipe
        .in("✅", "5")
        .code("(v => v | @vector/norm)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@vector/norm","status":0,"input":5,"expected":["_ ? @vector/Vector"]}')
    end
  end

  describe "@vector/cross" do
    it "computes the cross product of the first two unit vectors" do
      expect_pipe
        .in("✅", "[[1,0,0],[0,1,0]]")
        .code("(p => p | @vector/cross)")
        .out("✅", "[0,0,1]")
    end

    it "computes a general cross product" do
      expect_pipe
        .in("✅", "[[1,2,3],[4,5,6]]")
        .code("(p => p | @vector/cross)")
        .out("✅", "[-3,6,-3]")
    end

    it "errors on vectors that are not 3-dimensional" do
      expect_pipe
        .in("✅", "[[1,2],[3,4]]")
        .code("(p => p | @vector/cross)")
        .out("❌", '{"kind":"argument_error","origin":"stdlib","file":"<inline>","operation":"@vector/cross","status":0,"input":[[1,2],[3,4]],"expected":["[[_ ? @Number, _ ? @Number, _ ? @Number], [_ ? @Number, _ ? @Number, _ ? @Number]]"]}')
    end
  end
end
