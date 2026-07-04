# frozen_string_literal: true

# The `@math` builtin object bundles numeric functions and constants, reached as a
# member access (`@math.round`, `@math.pi`, …). `pi`/`e` are plain values; the rest
# are one-argument functions. Non-finite inputs to `round`/`floor`/`ceil` and
# domain errors (log of a non-positive, complex `pow`) are `math_error`s.
RSpec.describe "@math builtin" do
  describe "constants" do
    it "@math.pi" do
      expect_pipe
        .in("✅", "null")
        .code("(_ => @math.pi)")
        .out("✅", "3.141592653589793")
    end

    it "@math.e" do
      expect_pipe
        .in("✅", "null")
        .code("(_ => @math.e)")
        .out("✅", "2.718281828459045")
    end
  end

  describe "@math.round" do
    it "rounds half away from zero" do
      expect_pipe
        .in("✅", "2.5")
        .code("(n => n | @math.round)")
        .out("✅", "3")
    end

    it "rounds a negative half away from zero" do
      expect_pipe
        .in("✅", "-2.5")
        .code("(n => n | @math.round)")
        .out("✅", "-3")
    end

    it "leaves an integer unchanged" do
      expect_pipe
        .in("✅", "5")
        .code("(n => n | @math.round)")
        .out("✅", "5")
    end

    it "errors with math_error on a non-finite number" do
      expect_pipe
        .in("✅", "null")
        .code("(_ => 1e400 | @math.round)")
        .out("❌", '{"kind":"math_error","origin":"builtin","file":"<inline>","operation":"@math.round","status":0,"input":"<Infinity>","message":"not a finite number"}')
    end

    it "errors on a non-number" do
      expect_pipe
        .in("✅", '"x"')
        .code("(n => n | @math.round)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@math.round","status":0,"input":"x","expected":["_ ? @Number"]}')
    end
  end

  describe "@math.floor" do
    it "floors toward minus infinity" do
      expect_pipe
        .in("✅", "-2.1")
        .code("(n => n | @math.floor)")
        .out("✅", "-3")
    end

    it "errors with math_error on a non-finite number" do
      expect_pipe
        .in("✅", "null")
        .code("(_ => 1e400 | @math.floor)")
        .out("❌", '{"kind":"math_error","origin":"builtin","file":"<inline>","operation":"@math.floor","status":0,"input":"<Infinity>","message":"not a finite number"}')
    end
  end

  describe "@math.ceil" do
    it "ceils toward plus infinity" do
      expect_pipe
        .in("✅", "2.1")
        .code("(n => n | @math.ceil)")
        .out("✅", "3")
    end

    it "ceils a negative toward zero" do
      expect_pipe
        .in("✅", "-2.9")
        .code("(n => n | @math.ceil)")
        .out("✅", "-2")
    end
  end

  describe "@math.divide" do
    it "always yields a float" do
      expect_pipe
        .in("✅", "[6,3]")
        .code("(p => p | @math.divide)")
        .out("✅", "2.0")
    end

    it "divides to a fraction" do
      expect_pipe
        .in("✅", "[7,2]")
        .code("(p => p | @math.divide)")
        .out("✅", "3.5")
    end

    it "errors with math_error on division by zero" do
      expect_pipe
        .in("✅", "[1,0]")
        .code("(p => p | @math.divide)")
        .out("❌", '{"kind":"math_error","origin":"builtin","file":"<inline>","operation":"@math.divide","status":0,"input":[1,0],"message":"division by zero"}')
    end

    it "errors on a non-numeric pair" do
      expect_pipe
        .in("✅", '[1,"x"]')
        .code("(p => p | @math.divide)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@math.divide","status":0,"input":[1,"x"],"expected":["[_ ? @Number, _ ? @Number]"]}')
    end
  end

  describe "@math.sign" do
    it "is -1 for a negative" do
      expect_pipe
        .in("✅", "-3")
        .code("(n => n | @math.sign)")
        .out("✅", "-1")
    end

    it "is 0 for zero" do
      expect_pipe
        .in("✅", "0")
        .code("(n => n | @math.sign)")
        .out("✅", "0")
    end

    it "is 1 for a positive" do
      expect_pipe
        .in("✅", "2.5")
        .code("(n => n | @math.sign)")
        .out("✅", "1")
    end

    it "errors on a non-number" do
      expect_pipe
        .in("✅", '"x"')
        .code("(n => n | @math.sign)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@math.sign","status":0,"input":"x","expected":["_ ? @Number"]}')
    end
  end

  describe "@math.abs" do
    it "takes the absolute value of an integer" do
      expect_pipe
        .in("✅", "-3")
        .code("(n => n | @math.abs)")
        .out("✅", "3")
    end

    it "preserves float-ness" do
      expect_pipe
        .in("✅", "-2.5")
        .code("(n => n | @math.abs)")
        .out("✅", "2.5")
    end
  end

  # @math.rand is non-deterministic; assert its type/shape, not an exact value.
  describe "@math.rand" do
    it "returns a float in [0, 1) for null" do
      expect_pipe
        .in("✅", "null")
        .code("(v => v | @math.rand | @Float)")
        .out("✅", "true")
    end

    it "returns an integer for a positive integer bound" do
      expect_pipe
        .in("✅", "5")
        .code("(n => n | @math.rand | @Integer)")
        .out("✅", "true")
    end

    it "errors on a non-positive integer" do
      expect_pipe
        .in("✅", "-1")
        .code("(n => n | @math.rand)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@math.rand","status":0,"input":-1,"expected":["_ ? @Null","_ ? (n ? @Integer => [0, n] | @OP.compare | (-1 => true))"]}')
    end
  end

  describe "trigonometric / transcendental" do
    it "@math.sin(0) is 0.0" do
      expect_pipe
        .in("✅", "0")
        .code("(n => n | @math.sin)")
        .out("✅", "0.0")
    end

    it "@math.cos(0) is 1.0" do
      expect_pipe
        .in("✅", "0")
        .code("(n => n | @math.cos)")
        .out("✅", "1.0")
    end

    it "@math.exp(0) is 1.0" do
      expect_pipe
        .in("✅", "0")
        .code("(n => n | @math.exp)")
        .out("✅", "1.0")
    end

    it "@math.exp(1) is e" do
      expect_pipe
        .in("✅", "1")
        .code("(n => n | @math.exp)")
        .out("✅", "2.718281828459045")
    end

    it "@math.log(1) is 0.0" do
      expect_pipe
        .in("✅", "1")
        .code("(n => n | @math.log)")
        .out("✅", "0.0")
    end

    it "@math.log errors on a non-positive number" do
      expect_pipe
        .in("✅", "0")
        .code("(n => n | @math.log)")
        .out("❌", '{"kind":"math_error","origin":"builtin","file":"<inline>","operation":"@math.log","status":0,"input":0,"message":"log of a non-positive number"}')
    end
  end

  describe "@math.pow" do
    it "is exact for an integer base and non-negative integer exponent" do
      expect_pipe
        .in("✅", "[2,10]")
        .code("(p => p | @math.pow)")
        .out("✅", "1024")
    end

    it "is a float for a negative exponent" do
      expect_pipe
        .in("✅", "[2,-1]")
        .code("(p => p | @math.pow)")
        .out("✅", "0.5")
    end

    it "is a float for a fractional exponent" do
      expect_pipe
        .in("✅", "[2,0.5]")
        .code("(p => p | @math.pow)")
        .out("✅", "1.4142135623730951")
    end

    it "errors with math_error on a complex result (negative base, fractional exponent)" do
      expect_pipe
        .in("✅", "[-1,0.5]")
        .code("(p => p | @math.pow)")
        .out("❌", '{"kind":"math_error","origin":"builtin","file":"<inline>","operation":"@math.pow","status":0,"input":[-1,0.5],"message":"not in domain (complex result)"}')
    end
  end

  describe "@math.sqrt" do
    it "takes a square root (float)" do
      expect_pipe
        .in("✅", "4")
        .code("(n => n | @math.sqrt)")
        .out("✅", "2.0")
    end

    it "is a float even for a non-perfect square" do
      expect_pipe
        .in("✅", "2")
        .code("(n => n | @math.sqrt)")
        .out("✅", "1.4142135623730951")
    end

    it "is 0.0 at zero" do
      expect_pipe
        .in("✅", "0")
        .code("(n => n | @math.sqrt)")
        .out("✅", "0.0")
    end

    it "errors with math_error on a negative number" do
      expect_pipe
        .in("✅", "-1")
        .code("(n => n | @math.sqrt)")
        .out("❌", '{"kind":"math_error","origin":"builtin","file":"<inline>","operation":"@math.sqrt","status":0,"input":-1,"message":"square root of a negative number"}')
    end

    it "errors on a non-number" do
      expect_pipe
        .in("✅", '"x"')
        .code("(n => n | @math.sqrt)")
        .out("❌", '{"kind":"argument_error","origin":"builtin","file":"<inline>","operation":"@math.sqrt","status":0,"input":"x","expected":["_ ? @Number"]}')
    end
  end
end
