# frozen_string_literal: true

# End-to-end runs of the example programs in spec/fixtures/.
RSpec.describe "example programs" do
  it "doubles a number" do
    expect_pipe
      .in("✅", "21")
      .file_path("double.fsn")
      .out("✅", "42")
  end

  it "swaps a pair" do
    expect_pipe
      .in("✅", "[1,2]")
      .file_path("swap.fsn")
      .out("✅", "[2,1]")
  end

  describe "fact (self-recursion via @fact)" do
    it "computes a factorial" do
      expect_pipe
        .in("✅", "5")
        .file_path("fact.fsn")
        .out("✅", "120")
    end

    it "treats 0! as 1" do
      expect_pipe
        .in("✅", "0")
        .file_path("fact.fsn")
        .out("✅", "1")
    end

    it "errors on a non-integer (strict)" do
      expect_pipe
        .in("✅", '"x"')
        .file_path("fact.fsn")
        .out("❌", "null")
    end
  end

  describe "sum (self-recursion via @sum)" do
    it "sums a list" do
      expect_pipe
        .in("✅", "[1,2,3,4]")
        .file_path("sum.fsn")
        .out("✅", "10")
    end

    it "sums the empty list to 0" do
      expect_pipe
        .in("✅", "[]")
        .file_path("sum.fsn")
        .out("✅", "0")
    end
  end

  it "maps over a list (uses @double + @map)" do
    expect_pipe
      .in("✅", "[1,2,3]")
      .file_path("main.fsn")
      .out("✅", "[2,4,6]")
  end

  describe "fizzbuzz" do
    it "says FizzBuzz for multiples of 15" do
      expect_pipe
        .in("✅", "15")
        .file_path("fizzbuzz.fsn")
        .out("✅", '"FizzBuzz"')
    end

    it "says Fizz for multiples of 3" do
      expect_pipe
        .in("✅", "9")
        .file_path("fizzbuzz.fsn")
        .out("✅", '"Fizz"')
    end

    it "says Buzz for multiples of 5" do
      expect_pipe
        .in("✅", "10")
        .file_path("fizzbuzz.fsn")
        .out("✅", '"Buzz"')
    end

    it "keeps the number otherwise" do
      expect_pipe
        .in("✅", "7")
        .file_path("fizzbuzz.fsn")
        .out("✅", "7")
    end
  end

  describe "safeDivide" do
    it "divides" do
      expect_pipe
        .in("✅", "[10,2]")
        .file_path("safeDivide.fsn")
        .out("✅", "5")
    end

    it "returns an error on division by zero" do
      expect_pipe
        .in("✅", "[10,0]")
        .file_path("safeDivide.fsn")
        .out("❌", "null")
    end
  end
end
