# frozen_string_literal: true

# Payloaded errors: construction, matching, propagation and recovery.
RSpec.describe "payloaded errors" do
  describe "construction" do
    it "wraps an integer payload" do
      expect_pipe
        .in("✅", "null")
        .code("(_ => !42)")
        .out("❌", "42")
    end

    it "wraps a string payload" do
      expect_pipe
        .in("✅", "null")
        .code('(_ => !"oops")')
        .out("❌", '"oops"')
    end

    it "wraps null" do
      expect_pipe
        .in("✅", "null")
        .code("(_ => !null)")
        .out("❌", "null")
    end

    it "treats bare ! as shorthand for !null" do
      expect_pipe
        .in("✅", "null")
        .code("(_ => !)")
        .out("❌", "null")
    end

    it "wraps an array payload" do
      expect_pipe
        .in("✅", "null")
        .code("(_ => ![1,2,3])")
        .out("❌", "[1,2,3]")
    end

    it "wraps an object payload" do
      expect_pipe
        .in("✅", "null")
        .code('(_ => !{"code":"x"})')
        .out("❌", '{"code":"x"}')
    end

    it "uses a captured value as the payload" do
      expect_pipe
        .in("✅", "42")
        .code("(x => !x)")
        .out("❌", "42")
    end

    it "uses a bound array to build the payload" do
      expect_pipe
        .in("✅", "[1,2]")
        .code('([a,b] => !{"left":a,"right":b})')
        .out("❌", '{"left":1,"right":2}')
    end
  end

  describe "matching on errors" do
    it "does not let a bare ! pattern match a non-error (null)" do
      expect_pipe
        .in("✅", "null")
        .code('(! => "caught", x => "fine")')
        .out("✅", '"fine"')
    end

    it "lets a bare ! pattern match a real error" do
      expect_pipe
        .in("✅", "42")
        .code('(x => !x | (! => "caught", _ => "no"))')
        .out("✅", '"caught"')
    end

    it "lets !_ match any error (different payload)" do
      expect_pipe
        .in("✅", '"oops"')
        .code('(x => !x | (!_ => "caught", _ => "no"))')
        .out("✅", '"caught"')
    end

    it "catches a produced error with bare !" do
      expect_pipe
        .in("✅", "5")
        .code('(x => ([x,0] | @divide) | (! => "caught"))')
        .out("✅", '"caught"')
    end

    it "catches with !_ and no binding" do
      expect_pipe
        .in("✅", "5")
        .code('(x => ([x,0] | @divide) | (!_ => "caught"))')
        .out("✅", '"caught"')
    end

    it "binds the payload with !msg" do
      expect_pipe
        .in("✅", "5")
        .code('(x => ([x,0] | @divide) | (!msg => msg))')
        .out("✅", '{"kind":"math_error","location":"builtin divide","operation":"divide","input":[5,0],"message":"division by zero"}')
    end

    it "matches a literal payload with !42" do
      expect_pipe
        .in("✅", "42")
        .code('(x => !x | (!42 => "got 42", !other => "got something else"))')
        .out("✅", '"got 42"')
    end

    it "does not match !42 against a different payload" do
      expect_pipe
        .in("✅", "99")
        .code('(x => !x | (!42 => "got 42", !other => "got something else"))')
        .out("✅", '"got something else"')
    end

    it "destructures an object payload with !{\"code\":c}" do
      expect_pipe
        .in("✅", "null")
        .code('(_ => !{"code":"X","msg":"hi"} | (!{"code":c} => c))')
        .out("✅", '"X"')
    end
  end

  describe "propagation" do
    it "preserves the payload through an unrelated function" do
      expect_pipe
        .in("✅", "5")
        .code('(x => ([x,0] | @divide) | (n => [n, 1] | @add))')
        .out("❌", '{"kind":"math_error","location":"builtin divide","operation":"divide","input":[5,0],"message":"division by zero"}')
    end

    it "returns !null on a strict no-match (not the propagated input error)" do
      expect_pipe
        .in("✅", "null")
        .code('(_ => null | (1 => "one", _ => !))')
        .out("❌", "null")
    end

    it "propagates the inner error of a nested ! rather than wrapping it (!!)" do
      expect_pipe
        .in("✅", "5")
        .code("(x => !([x,0] | @divide))")
        .out("❌", '{"kind":"math_error","location":"builtin divide","operation":"divide","input":[5,0],"message":"division by zero"}')
    end
  end

  describe "errors are not first-class values" do
    it "short-circuits an array literal at the first error element" do
      expect_pipe
        .in("✅", "null")
        .code("(_ => [!42, !99])")
        .out("❌", "42")
    end

    it "short-circuits an object literal at the first error value" do
      expect_pipe
        .in("✅", "null")
        .code('(_ => {"a": !42, "b": 1})')
        .out("❌", "42")
    end

    it "propagates an error through @equals (a literal [!42,!42] short-circuits)" do
      expect_pipe
        .in("✅", "null")
        .code("(_ => [!42, !42] | @equals)")
        .out("❌", "42")
    end

    it "propagates an error through @Integer" do
      expect_pipe
        .in("✅", "null")
        .code("(_ => !42 | @Integer)")
        .out("❌", "42")
    end

    it "can inspect a payload only after catching the error first" do
      expect_pipe
        .in("✅", "null")
        .code("(_ => !42 | (!a => a) | @Integer)")
        .out("✅", "true")
    end
  end

  describe "partial match across clauses" do
    it "returns the normal value when a payload pattern matches" do
      expect_pipe
        .in("✅", "null")
        .code('(_ => !42 | (!42 => "got 42", x => x))')
        .out("✅", '"got 42"')
    end

    it "propagates the original error when no payload pattern matches" do
      expect_pipe
        .in("✅", "null")
        .code('(_ => !99 | (!42 => "got 42", x => x))')
        .out("❌", "99")
    end

    it "propagates the original error across multiple error clauses" do
      expect_pipe
        .in("✅", "null")
        .code('(_ => !"oops" | (!42 => "a", !99 => "b"))')
        .out("❌", '"oops"')
    end

    it "still returns null for a non-error input with no matching clause" do
      expect_pipe
        .in("✅", "null")
        .code('(_ => 5 | (1 => "one", 2 => "two"))')
        .out("✅", "null")
    end
  end

  describe "invalid input" do
    it "reports non-JSON input as a parse_error payload (located at the input channel)" do
      expect_pipe
        .in("✅", "not json")
        .code("(x => x)")
        .out("❌", '{"kind":"parse_error","location":"input","operation":"parsing input as JSON","input":"not json","message":"input is not valid JSON"}')
    end
  end

  describe "recovery via an explicit ! clause" do
    it "catches an error with an explicit ! clause" do
      expect_pipe
        .in("✅", "null")
        .code("(! => 0, x => x)")
        .out("✅", "null")
    end

    it "recovers a produced error by piping into a recovery clause" do
      expect_pipe
        .in("✅", "5")
        .code("(x => ([x,0] | @divide) | (! => 999, y => y))")
        .out("✅", "999")
    end
  end
end
