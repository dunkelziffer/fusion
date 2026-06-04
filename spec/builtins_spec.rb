# frozen_string_literal: true

# Built-in operations piped via @name.
RSpec.describe "builtins" do
  describe "@divide" do
    it "errors on division by zero" do
      expect_pipe
        .in("✅", "[1,0]")
        .code("(p => p | @divide)")
        .out("❌", '"divide: division by zero"')
    end
  end

  describe "@add" do
    it "errors on a non-numeric pair" do
      expect_pipe
        .in("✅", '["a","b"]')
        .code("(p => p | @add)")
        .out("❌", '"add: expected a pair of numbers"')
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
