# frozen_string_literal: true

# Built-in operations piped via @name.
RSpec.describe "builtins" do
  describe "@divide" do
    it "errors on division by zero" do
      expect_pipe
        .in("✅", "[1,0]")
        .code("(p => p | @divide)")
        .out("❌", '{"kind":"math_error","location":"builtin divide","operation":"divide","input":[1,0],"message":"division by zero"}')
    end
  end

  describe "@add" do
    it "errors with type_error on a pair of the wrong type" do
      expect_pipe
        .in("✅", '["a","b"]')
        .code("(p => p | @add)")
        .out("❌", '{"kind":"type_error","location":"builtin add","operation":"add","input":["a","b"],"message":"expected numbers"}')
    end

    it "errors with argument_error when the input is not a pair" do
      expect_pipe
        .in("✅", "[1,2,3]")
        .code("(p => p | @add)")
        .out("❌", '{"kind":"argument_error","location":"builtin add","operation":"add","input":[1,2,3],"message":"expected a pair"}')
    end
  end

  describe "@equals" do
    it "compares structurally (deep equality)" do
      expect_pipe
        .in("✅", "[[1,[2]],[1,[2]]]")
        .code("(p => p | @equals)")
        .out("✅", "true")
    end
  end
end
