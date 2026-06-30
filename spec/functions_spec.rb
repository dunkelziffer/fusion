# frozen_string_literal: true

# Functions as values: closures and currying.
RSpec.describe "functions" do
  it "reports a serialization_error for a bare function result (a closure is produced, but JSON can't hold it)" do
    expect_pipe
      .in("✅", "10")
      .code("(n => (m => [n, m] | @add))")
      .out("❌", '{"kind":"serialization_error","origin":"output","operation":"serializing result","status":0,"input":"<function>","message":"cannot serialize a function"}')
  end

  it "curries: 10 | (n => (m => n+m)) then applied to 5" do
    expect_pipe
      .in("✅", "[10,5]")
      .code("(pair => pair[0] | (n => (m => [n,m] | @add)) | (g => pair[1] | g))")
      .out("✅", "15")
  end

  describe "the empty function ()" do
    it "matches nothing, so a normal input becomes null" do
      expect_pipe
        .in("✅", "5")
        .code("()")
        .out("✅", "null")
    end

    it "propagates an error input" do
      expect_pipe
        .in("❌", '"boom"')
        .code("()")
        .out("❌", '"boom"')
    end
  end
end
